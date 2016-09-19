crypto  = require 'crypto'
fs      = require 'fs'
pathlib = require 'path'
glob    = require 'glob'
toposort = require 'toposort'

LEADING_SLASH_RE = /^\//

warn = (message) -> Digest.logger.warn "digest-brunch WARNING: #{message}"

class Digest
  brunchPlugin: true

  constructor: (@config) ->
    # Defaults options
    @options = {
      # A RegExp where the first subgroup matches the filename to be replaced
      pattern: /DIGEST\((\/?[^\)]*)\)/g
      # After replacing the filename, should we discard the non-filename parts of the pattern?
      discardNonFilenamePatternParts: yes
      # RegExp that matches files that contain filename references.
      referenceFiles: /\.html$/
      # How many digits of the SHA1 to append to digested files.
      precision: 8
      # Force digest-brunch to run in all environments when true.
      alwaysRun: false
      # Run in specific environments
      environments: ['production']
      # Prepend an absolute asset host URL to the file paths in the reference files
      prependHost: null
      # Output filename for a JSON manifest of reference file paths and their digest.
      manifest: ''
      # An array of infixes for alternate versions of files. This is useful when e.g. using retina.js (@2x) for high density images.
      infixes: []
    }

    # Merge config
    cfg = @config.plugins?.digest ? {}
    @options[k] = cfg[k] for k of cfg

    # Ensure that the pattern RegExp is global
    needle = @options.pattern.source or @options.pattern or ''
    flags = 'g'
    flags += 'i' if @options.pattern.ignoreCase
    flags += 'm' if @options.pattern.multiline
    @options.pattern = new RegExp(needle, flags)

  onCompile: ->
    @publicFolder = @config.paths.public
    filesToSearch = @_referenceFiles()

    # Check if the current environment is one we want to add digests for
    if (@config.env[0] not in @options.environments) and !@options.alwaysRun
      # Replace filename references with regular file name if not running.
      @_removeReferences(filesToSearch)
    else
      if @config.server?.run
        warn 'Not intended to be run with on-demand compilation (brunch watch)'

      if @options.precision < 6
        warn 'Name collision more likely when less than 6 digits of SHA used.'

      sortedFilesToSearch = @_sortByDependencyGraph(filesToSearch)
      replacementDigestMap = {}
      for file in sortedFilesToSearch
        @_replaceFileDigests(file, replacementDigestMap)

      @_writeManifestFile(replacementDigestMap)

  _removeReferences: (files) ->
    return unless @options.discardNonFilenamePatternParts
    for file in files
      contents = fs.readFileSync(file).toString()
      contents = contents.replace(@options.pattern, '$1')
      fs.writeFileSync(file, contents)

  # All files matching the `referenceFiles` regexp.
  # These are the target search and replace files.
  _referenceFiles: ->
    allUrls = glob.sync('**', { cwd: @publicFolder })
    referenceFiles = []
    for url in allUrls
      file = @_fileFromUrl url
      referenceFiles.push file if @options.referenceFiles.test(file)
    referenceFiles

  # Because dependencies may contain other dependencies,
  # we will proceed in order of increasing dependency.
  _sortByDependencyGraph: (files) ->
    graph = []
    for file in files
      # Reset the pattern's internal match tracker
      @options.pattern.lastIndex = 0
      contents = fs.readFileSync(file, 'UTF-8')
      match = @options.pattern.exec(contents)
      while match isnt null
        url = match[1]
        dependency = @_fileFromUrl url, file
        graph.push [dependency, file]
        match = @options.pattern.exec(contents)
    sorted = toposort(graph)
    sorted.filter (file) ->
      files.indexOf(file) >= 0

  # The filename a digest url should map to.
  _fileFromUrl: (url, referencedFrom) ->
    if referencedFrom and url[0] != '/'
      dir = pathlib.dirname(referencedFrom)
    else
      dir = @publicFolder
    file = pathlib.join(dir, url)
    pathlib.normalize(file)

  # Search and replace a single reference file.
  # All digest urls encountered will be mapped to a real file,
  # the file will be hashed and renamed with its hash,
  # and the url will be rewritten to include the hash.
  _replaceFileDigests: (file, digestMap) ->
    # Reset the pattern's internal match tracker
    @options.pattern.lastIndex = 0
    contents = fs.readFileSync(file, 'UTF-8')
    self = this
    replacement = contents.replace @options.pattern, (digest, url) ->
      hash = self._hashFromUrl url, file, digestMap
      urlWithHash = self._addHashToPath(url, hash)

      if self.options.prependHost?[self.config.env[0]]?
        urlWithHash = self.options.prependHost[self.config.env[0]] + urlWithHash

      if self.options.discardNonFilenamePatternParts
        urlWithHash
      else
        digest.replace url, urlWithHash

    fs.writeFileSync(file, replacement)

  # We're moving files and keeping their hashes as we go.
  # Returns the hash of a file.
  # Computes the hash and renames the file if needed.
  _hashFromUrl: (url, referencedFrom, digestMap) ->
    file = @_fileFromUrl url, referencedFrom
    if digestMap[file] == undefined
      if @_validDigestFile file
        hash = @_calculateHash file
        @_moveFile file, hash
        digestMap[file] = hash
      else
        digestMap[file] = null
    digestMap[file]

  _calculateHash: (file) ->
    data = fs.readFileSync file
    shasum = crypto.createHash 'sha1'
    shasum.update(data)
    shasum.digest('hex')[0..@options.precision-1]

  _moveFile: (file, hash) ->
    newFile = @_addHashToPath(file, hash)
    fs.renameSync(file, newFile)

    for infix in @options.infixes
      infixFile = @_addInfixToPath file, infix
      if fs.existsSync(infixFile)
        newInfixFile = @_addInfixToPath newFile, infix
        fs.renameSync(infixFile, newInfixFile)

  _validDigestFile: (file) ->
    if !fs.existsSync(file)
      warn "Missing hashed version of file #{file}. Skipping."
      return false
    fs.statSync(file).isFile()

  _addHashToPath: (path, hash) ->
    if hash
      dir = pathlib.dirname(path)
      ext = pathlib.extname(path)
      base = pathlib.basename(path, ext)
      newName = "#{base}-#{hash}#{ext}"
      pathlib.posix.join(dir, newName)
    else
      path

  _addInfixToPath: (path, infix) ->
    dir = pathlib.dirname(path)
    ext = pathlib.extname(path)
    base = pathlib.basename(path, ext)
    newName = "#{base}#{infix}#{ext}"
    pathlib.posix.join(dir, newName)

  _writeManifestFile: (renameMap) ->
    if not @options.manifest
      return
    manifest = {}
    for file, hash of renameMap when hash
      relative = pathlib.relative(@publicFolder, file).replace(/\\/g, '/')
      rename = @_addHashToPath relative, hash
      manifest[relative] = rename
    fs.writeFileSync(@options.manifest, JSON.stringify(manifest, null, 4))


Digest.logger = console

module.exports = Digest
