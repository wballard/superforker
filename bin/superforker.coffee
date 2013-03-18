#!/usr/bin/env ./node_modules/coffee-script/bin/coffee
# vim: set syntax=coffee:

doc = """
Superforker!

Usage:
    superforker start [PORT]
    superforker stop
    superforker poke

Arguments:
    PORT  TCP port, serves HTTP and socket IO here [default: 8080]
"""

{docopt} = require 'docopt'
path = require 'path'
crypto = require 'crypto'
child_process = require 'child_process'

options = docopt(doc)

#docopt doesn't quite understand defaults for positionals
options.PORT = options.PORT or '8080'

console.log options


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
        io = require('socket.io').listen(server)
        error_count = 0
        #running of commands via GET, nothing is routed to STDIN
        app.get '/*', (request, response) ->
            toRun = path.join process.cwd(), request.path
            child_process.execFile toRun, (error, stdout, stderr) ->
                if error
                    #big old error object in a JSON ball
                    error =
                        id: guid_like(Date.now(), error_count++)
                        at: Date.now()
                        error: error
                        message: stderr.toString()
                    response.end JSON.stringify(error)
                else
                    response.end(stdout)


        io.set 'log level', 0
        server.listen options.PORT
    stop: () ->
    poke: () ->

for verb, __ of options
    if verbs[verb]
        verbs[verb]()
