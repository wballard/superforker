#This is a root level command to export the superforker
#suite of command line actions.

fs = require 'fs'
path = require 'path'
child_process = require 'child_process'
package_json = JSON.parse fs.readFileSync path.join(__dirname, '../package.json')
server = require './server'
doc = """
#{package_json.description}

Usage:
    superforker [options] <port> <handlers> [<static>] [<requirejs>]

Options:
    --help
    --version

Description:
    Superforker will server the handler scripts rooted at <handlers> on <port>.
    Handler scripts are described in the package readme.

    Static files are served from the directory <static>.

    Require.js can be used to pre-optimize a root application by specifying a
    require.js build config file.
    You simply ask for this config file and it will return you a fully built and
    optimized require.js application.
    This config file needs to be served via static, so you must have static
    set in order to use this option.
    Example:
        dir/ /app.js will match a curl http://localhost/app.js loading from
        file path dir/app.js

"""
{docopt} = require 'docopt', version: package_json.version
options = docopt doc
process.env.SUPERFORKER_ROOT = path.join __dirname, '..'
process.env.ROOT = path.resolve options['<handlers>']
process.env.STATIC_ROOT = path.resolve options['<static>']
server options['<port>'], options['<handlers>'], options['<static>'], options['<requirejs>']

