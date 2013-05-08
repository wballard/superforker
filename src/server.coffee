path = require 'path'
fs = require 'fs'
crypto = require 'crypto'
child_process = require 'child_process'
repl = require 'repl'
io_client = require 'socket.io-client'
io = require 'socket.io'
url = require 'url'
util = require 'util'
_ = require 'underscore'
yaml = require 'js-yaml'
chokidar = require 'chokidar'
express = require 'express'
require 'colors'

#It's a bird, it's a plane, it's GUID-like!
guid_like = () ->
    hash = crypto.createHash 'md5'
    for argument in arguments
        hash.update "#{argument}", 'utf8'
    hash.digest 'hex'

module.exports = (port, root, static_root) ->
    #fire up express with socket io
    app = express()
    app.use express.compress()
    server = require('http').createServer(app)
    if static_root
        app.use express.static(static_root)
    io = io.listen(server)
    #hooking into the authorization handshake sequence
    io.configure ->
        io.set 'authorization', (handshakeData, callback) ->
            #looking for a well know query string token called
            #authtoken, which will be passed to a well known program
            #auth, passing that token as the one parameter
            #auth is expected to return the user identity on success
            #or exit code non-zero on failure
            authpath = path.join root, 'auth'
            fs.exists authpath, (exists) ->
                #if we didn't supply an auth program, well, we aren't going
                #to auth now are we...
                if not exists
                    handshakeData.USER = handshakeData.query.authtoken
                    callback null, true
                else
                    child_process.execFile authpath, [handshakeData.query.authtoken],
                        (error, stdout, stderr) ->
                            if error
                                util.error "authorization error #{stdout} #{stderr}".red
                                callback stderr, false
                            else
                                util.log "authorization success".green + stdout
                                handshakeData.USER = yaml.safeLoad stdout
                                callback null, true
    error_count = 0
    #big block of environment handling and setup
    setup_environment = (message, environment={}, user) ->
        environment =
            PATH_INFO: message.command
            SCRIPT_NAME: path.basename(message.path)
            USER: if _.isString(user)
                user
            else
                yaml.dump(user)
        #flag to look for stdin, really just for testing
        if message.stdin
            environment.READ_STDIN = "TRUE"
        else
            environment.READ_STDIN = "FALSE"
        _.extend {}, process.env, environment
    #message processing at its finest
    io.on 'connection', (socket) ->
        #file watching
        #per connection file watcher
        if not socket.watcher
            socket.watcher = chokidar.watch __filename,
                ignored: (item) ->
                    #'hidden' directories are skipped and chokidar is nice
                    #enough to then not recurse
                    path.basename(item).indexOf('.') is 0
        emitFileMessage = (message_name, filename) ->
            fs.readFile filename, (error, data) ->
                message =
                    filename: filename
                    error: error
                if data and path.extname(filename) is '.yaml'
                    message.data = yaml.safeLoad(data.toString())
                    message.object = true
                else
                    message.data = data and data.toString()
                #good to go
                socket.emit message_name, message
        socket.watcher.on 'add', (filename) ->
            emitFileMessage 'addFile', filename
        socket.watcher.on 'change', (filename) ->
            emitFileMessage 'changeFile', filename
        socket.watcher.on 'unlink', (filename) ->
            socket.emit 'unlinkFile',
                filename: filename
        #message handling
        #authentication callback, allows clients to know who they are and
        #request additional data
        if socket.handshake.USER
            util.log "connected as #{socket.handshake.USER}"
            socket.emit 'hello', socket.handshake.USER
        #disconnection clears up the watcher
        socket.on 'disconnect', ->
            util.log "disconnected as #{socket.handshake.USER}"
            if socket.watcher
                socket.watcher.close()
        #these are really just for testing, and likely need ot be turned off
        socket.on 'unlinkFile', (message) ->
            fs.unlink message.path, ->
                socket.emit 'unlinkFileComplete',
                    path: message.path
        socket.on 'writeFile', (message) ->
            fs.writeFile message.path, message.content, ->
                socket.emit 'writeFileComplete',
                    path: message.path
        #install file watching with this message
        socket.on 'watch', (message) ->
            #add the watched directory, checking for duplicates
            if not socket.watcher[message.directory]
                socket.watcher.add message.directory
            #keep track of the message for the directory, think of this as
            #the options
            socket.watcher[message.directory] = message
        socket.on 'exec', (message, ack) ->
            message.path = path.join root, message.command
            child_options =
                env: setup_environment(message, {}, socket.handshake.USER)
            childProcess = child_process.execFile message.path, message.args, child_options,
                (error, stdout, stderr) ->
                    if error
                        #big old error object in a JSON ball
                        error =
                            id: guid_like(Date.now(), error_count++)
                            at: Date.now()
                            error: error
                            message: stderr
                        errorString = JSON.stringify(error)
                        #for out own output so we can sweep this up in server logs
                        process.stderr.write errorString
                        process.stderr.write "\n"
                        socket.emit 'error', error
                        #non zero exit code, we are toast and not going
                        #on to any potential ack
                        return
                    else
                        #trap the stderr on the server here, no process
                        #exit code, just informational content, i.e.
                        #we only return stdout back in the messages
                        process.stderr.write stderr
                    if ack
                        #socket io synchronous callback case
                        try
                            ack(yaml.safeLoad(stdout))
                        catch error
                            ack(stdout)
                    else
                        #or just a message back
                        try
                            socket.emit 'exec', yaml.safeLoad(stdout)
                        catch error
                            socket.emit 'exec', stdout
            #if we have content, pipe it along to the forked process
            if message.stdin
                childProcess.stdin.on 'error', ->
                    util.log "error on stdin #{arguments}"
                childProcess.stdin.end JSON.stringify(message.stdin)
    #have socket.io not yell so much
    io.set 'log level', 0
    util.log "server start #{process.pid}".green
    util.log "serving handlers from #{root} with node #{process.version}".blue
    if static_root
        util.log "serving static from #{static_root} with node #{process.version}".blue
    process.on 'exit', ->
        util.log "server shutdown #{process.pid}".red
    server.listen port
