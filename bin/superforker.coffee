#!/usr/bin/env ./node_modules/coffee-script/bin/coffee
# vim: set syntax=coffee:

doc = """
Superforker!

Usage:
    superforker start [PORT] [--root=<root>]
    superforker stop
    superforker poke

Options:
    --root=<root>    Root directory, forked processes are relative to this.

Arguments:
    PORT  TCP port, serves HTTP and socket IO here [default: 8080]
"""

{docopt} = require 'docopt'
path = require 'path'
crypto = require 'crypto'
child_process = require 'child_process'
repl = require 'repl'
io_client = require 'socket.io-client'
io = require 'socket.io'
url = require 'url'

DEFAULT_PORT = '8080'

options = docopt(doc)

#docopt doesn't quite understand defaults for positionals
options.PORT = options.PORT or DEFAULT_PORT


#It's a bird, it's a plane, it's GUID-like!
guid_like = () ->
    hash = crypto.createHash 'md5'
    for argument in arguments
        hash.update "#{argument}", 'utf8'
    hash.digest 'hex'

#here are all the root level verbs, options will be in scope, so
#we aren't bothering to pass them, just nice places so each has their
#own function induced variable scope
verbs =
    start: () ->
        #fire up express with socket io
        app = require('express')()
        server = require('http').createServer(app)
        io = io.listen(server)
        error_count = 0
        cwd = options['--root'] or process.cwd()
        #big block of
        setup_environment = (request, environment={}) ->
            environment =
                METHOD: request.method
                PATH_INFO: request.path
                SCRIPT_NAME: path.basename(request.path)
                SERVER_PORT: options.PORT
                SERVER_NAME: request.host
            if request.method is 'POST' or request.content
                environment.READ_STDIN = "TRUE"
            else
                environment.READ_STDIN = "FALSE"
            environment
        #running of commands via GET, nothing is routed to STDIN
        handleError = (response, error, stdout, stderr) ->
            #big old error object in a JSON ball
            error =
                id: guid_like(Date.now(), error_count++)
                at: Date.now()
                error: error
                message: stderr.toString()
            errorString = JSON.stringify(error)
            #for out own output so we can sweep this up in server logs
            process.stderr.write errorString
            process.stderr.write "\n"
            #tiny bit different if raw http or socketio
            if response.socketio
                response.status(500).end error
            else
                response.status(500).end errorString
        #this is our big bad forker
        runIt = (request, response, callback) ->
            toRun = path.join cwd, request.path
            console.log toRun, process.cwd()
            response.set 'Content-Type', 'application/json'
            child_options =
              env: setup_environment(request, {})
            #turn query parameters
            args = []
            for name, value of request.query
                args.push "--#{name}", "#{value}"
            child_process.execFile toRun, args, child_options, callback
        #GET doesn't need to hook up the stdin, it just forks and
        #writes back out
        app.get '/*', (request, response) ->
            runIt request, response, (error, stdout, stderr) ->
                if error
                    handleError response, error, stdout, stderr
                else
                    #and a program that runs just fine, go ahead and
                    #just send back the results, we're counting on you
                    #to return JSON, since we are telling the client this
                    #is going to be JSON above
                    response.end(stdout)
                    #and we'll keep the error bits to our server for logging
                    process.stderr.write stderr
        #POST is a lot like GET, but we don't repeat the comments
        app.post '/*', (request, response) ->
            childProcess = runIt request, response, (error, stdout, stderr) ->
                if error
                    handleError response, error, stdout, stderr
                else
                    process.stderr.write stderr
                    response.end(stdout)
            childProcess.stdin.on 'error', ->
                console.log "error on stdin #{arguments}"
            #stream along the body
            request.on 'data', (chunk) ->
                childProcess.stdin.write chunk
            request.on 'end', ->
                childProcess.stdin.end()
        #ultra wildcard message listening
        io.on 'connection', (socket) ->
            socket.$emit = (name, content, ack) ->
                parsed = url.parse(name)
                #fake http request
                request =
                    method: 'SOCKETIO'
                    path: parsed.pathname
                    query: parsed.query
                    host: ''
                    content: content
                #fake http reponse
                response =
                    socketio: true
                    code: 200
                    set: ->
                    status: (code) ->
                        response.code = code
                        response
                    end: (stuff) ->
                        if ack
                            ack(stuff)
                        else
                            socket.emit name, stuff
                #fork and work
                childProcess = runIt request, response, (error, stdout, stderr) ->
                    if error
                        handleError response, error, stdout, stderr
                    else
                        process.stderr.write stderr
                        response.end(stdout)
                if content
                    childProcess.stdin.on 'error', ->
                        console.log "error on stdin #{arguments}"
                    childProcess.stdin.end JSON.stringify(content)
        io.set 'log level', 0
        server.listen options.PORT
    stop: () ->
    poke: () ->
        #this starts up a command line repl, so there are 'sub verbs in here'
        socket = null
        #and here we start
        poker = repl.start
            prompt: ":)"
            input: process.stdin
            output: process.stdout
        .on 'exit', ->
            console.log 'cya'
        #hook on up
        poker.context.connect = (host, port) ->
            socket = io_client.connect("http://#{host}:#{port}")
            socket.on 'connect', ->
                console.log "connected #{host}:#{port}"
        #send a message if already connected
        poker.context.send = (name, content) ->
            socket.emit name, content, (reply) ->
                console.log "reply: #{reply}"
        #use this for self test
        poker.context.test = (host, port, name, content) ->
            socket = io_client.connect("http://#{host}:#{port}")
            socket.on 'connect', ->
                socket.emit name, content, (reply) ->
                    console.log "reploy to poke #{reply}"
                    process.exit()
            ''

#
for verb, __ of options
    if verbs[verb] and options[verb]
        verbs[verb]()
