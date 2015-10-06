#!/usr/bin/env iced
#
# iced radio.iced "http://localhost:8000/di-progressive#DI.fm progressive" "http://localhost:8000/pure-progressive#Pure.fm progressive"
#
# TIP: for aac in *.aac; do m4a=$(basename "$aac" .aac).m4a; ffmpeg -i "$aac" -vn -acodec copy -bsf:a aac_adtstoasc "$m4a"; done
#
# TODO metadata precedes track change; overlap?
# TODO ID3v2.3
# TODO mp4edit to wrap AAC (or is that a downstream problem?)

events     = require 'events'
fs         = require 'fs'
path       = require 'path'
url        = require 'url'
icy        = require 'icy'
sanitize   = require 'sanitize-filename'

mimeTypes =
    'audio/aac':  'aac'
    'audio/mpeg': 'mp3'

agent = 'stream archiver'

defaultArchiveDir = 'archive'


class Archiver extends events.EventEmitter
    breather: 3000

    constructor: (@inboundURL, @archiveDir) ->
        super()
        @inbound       = null
        @metadata      = null
        @archivePath   = null
        @archive       = null

    run: ->
        do =>
            loop
                await @connect defer err
                unless err
                    await @inbound.on('end', defer())
                    await fs.unlink(@archivePath + '.new', defer())
                await setTimeout(defer(), @breather)
                console.log "retrying #{@inboundURL}"
        return this

    connect: (cb) =>
        await
            @metadata = null
            done = defer err, @inbound
            options = url.parse(@inboundURL)
            options.headers = {'user-agent': agent}
            icy.get(options, (inbound) => done(null, inbound))
                .on('error', done)
        return cb?(err) if err

        @inbound.on 'metadata', (metadata) =>
            firstMetadata = not @metadata
            @metadata = icy.parse(metadata)

            if @archive
                @inbound.unpipe(@archive)
                @archive.close()
                @archive = null

            if @archivePath
                fs.rename @archivePath + '.new', @archivePath, ->
                @emit('ended', @archivePath)
                @archivePath = null

            if @archiveDir
                title = @metadata.StreamTitle
                if firstMetadata
                    title = "#{title} PARTIAL"
                extension = mimeTypes[@inbound.headers['content-type']] ? 'mp3'
                @archivePath = path.join(@archiveDir, "#{sanitize(title)}.#{extension}")
                @archive = fs.createWriteStream(@archivePath + '.new')
                @emit('started', @archivePath)
                @inbound.pipe(@archive)
        cb()
        

if require.main is module
    [_, _, argv...] = process.argv

    for channel, i in argv
        [inboundURL, archiveDir] = channel.split('#')
        archiveDir ?= defaultArchiveDir
        a = new Archiver(inboundURL, archiveDir)
        a.on('ended', (path) -> console.log(path))
        a.run()


module.exports = {Archiver}
