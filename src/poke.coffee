doc = """
Superforker Poke! The Superpoker!

Usage:
    poke

"""
{docopt} = require 'docopt'
repl = require 'repl'
io_client = require 'socket.io-client'
util = require 'util'
path = require 'path'
sleep = require 'sleep'

options = docopt(doc)

do () ->
    #this starts up a command line repl, so there are 'sub verbs in here'
    socket = null
    #and here we start
    poker = repl.start
        prompt: ":)"
        input: process.stdin
        output: process.stdout
    .on 'exit', ->
        console.log 'cya'
    #use this for self test
    poker.context.test = (host, port, name, content, args) ->
        message =
            command: name
            stdin: content
            args: args
        socket = io_client.connect("http://#{host}:#{port}?authtoken=superpoker")
        socket.on 'connect', ->
            socket.emit 'exec', message, (reply) ->
                console.log "reply to poke #{reply}"
                process.exit()
        setTimeout (-> process.exit(1)), 2000
        ''
    #use this for self test file watching
    poker.context.test_watch = (host, port, directory) ->
        message =
            directory: directory
        socket = io_client.connect("http://#{host}:#{port}?authtoken=superpoker")
        socket.on 'connect', ->
            socket.emit 'watch', message
            socket.emit 'writeFile',
                path: path.join directory, 'a.txt'
                content: 'Hello'
        socket.on 'addFile', (message) ->
            console.log 'add', message.filename
            sleep.sleep 1
            socket.emit 'writeFile',
                path: path.join directory, 'a.txt'
                content: 'World'
        socket.on 'changeFile', (message) ->
            console.log 'change', message.filename
            sleep.sleep 1
            socket.emit 'unlinkFile',
                path: path.join directory, 'a.txt'
        socket.on 'unlinkFile', (message) ->
            console.log 'unlink', message.filename
            process.exit()
        setTimeout (-> process.exit(1)), 5000
        ''

