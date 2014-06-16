crypto  = require 'crypto'
fs      = require 'fs'
pathlib = require 'path'
glob    = require 'glob'

LEADING_SLASH_RE = /^\//

warn = (message) -> console.warn "digest-brunch WARNING: #{message}"

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
    allFiles = glob.sync("#{@publicFolder}/**")
    referenceFiles = @_referenceFiles(allFiles)

    # Check if the current environment is one we want to add digests for
    if (@config.env[0] not in @options.environments) and !@options.alwaysRun
      # Replace filename references with regular file name if not running.
      @_removeReferences(referenceFiles)
    else
      if @config.server?.run
        warn 'Not intended to be run with on-demand compilation (brunch watch)'

      if @options.precision < 6
        warn 'Name collision more likely when less than 6 digits of SHA used.'

      filesToDigest = @_filesToDigest(referenceFiles)
      filesAndDigests = @_filesAndDigests(filesToDigest)
      renameMap = @_renameMap(filesAndDigests)
      if @options.manifest
        fs.writeFileSync(@options.manifest, JSON.stringify(renameMap, null, 4))
      @_renameAndReplace(referenceFiles, renameMap)

  _validDigestFile: (file) ->
    if !fs.existsSync(file)
      warn "Missing hashed version of file #{file}. Skipping."
      return false

    fs.statSync(file).isFile()

  _referenceFiles: (files) ->
    referenceFiles = []
    for file in files
      referenceFiles.push file if @options.referenceFiles.test(file)
    referenceFiles

  # Internal: Find files that need a digest in all valid reference files.
  #
  # files - An array of files that may contain digest references.
  #
  # Returns an array of filenames.
  _filesToDigest: (files) ->
    filesToDigest = []
    for file in files
      # Reset the pattern's internal match tracker
      @options.pattern.lastIndex = 0

      contents = fs.readFileSync(file).toString()
      match = @options.pattern.exec(contents)
      while match isnt null
        filesToDigest.push match[1]
        match = @options.pattern.exec(contents)

    filesToDigest

  # Internal: Generate a hash of filenames to their digests.
  #
  # files - An array of files.
  #
  # Returns an object with keys of filenames and value of the digest.
  _filesAndDigests: (files) ->
    precision = @options.precision
    filesAndDigests = {}
    for file in files
      hasLeadingSlash = LEADING_SLASH_RE.test(file)
      file = pathlib.join(@publicFolder, file)
      if @_validDigestFile(file)
        data = fs.readFileSync file
        shasum = crypto.createHash 'sha1'
        shasum.update(data)
        relativePath = pathlib.relative(@publicFolder, file)
        relativePath = "/#{relativePath}" if hasLeadingSlash
        filesAndDigests[relativePath] = shasum.digest('hex')[0..precision-1]
    filesAndDigests

  _renameAndReplace: (referenceFiles, renameMap) ->
    # Generate a name map
    nameMap = {}
    for originalFilename, newFilename of renameMap
      originalPath = pathlib.join(@publicFolder, originalFilename)
      newPath = pathlib.join(@publicFolder, newFilename)
      nameMap[originalPath] = newPath

    # Perform the renames
    fs.renameSync(originalPath, newPath) for originalPath, newPath of nameMap

    # Replace occurances of that file in reference files.
    @_replaceReferences(referenceFiles, renameMap)

  # Internal: Make a mapping of files to their renamed version containing the
  # digest.
  #
  # filesAndDigests - an object with keys of filenames and value of the
  # digest.
  #
  # Returns an object with keys of filenames and values of the new filename
  _renameMap: (filesAndDigests) ->
    renameMap = {}
    for path, digest of filesAndDigests
      directory = pathlib.dirname(path)
      extname = pathlib.extname(path)
      filename = pathlib.basename(path, extname)
      digestFilename = "#{filename}-#{digest}#{extname}"
      digestPath = pathlib.join(directory, digestFilename)
      renameMap[path] = digestPath
    renameMap

  # A function to escape a regular expression
  # Taken from http://stackoverflow.com/a/6969486
  _escapeRegExp: (str) ->
    str.replace /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&"

  _replaceReferences: (referenceFiles, renamedFiles) ->
    for referenceFile in referenceFiles
      # Store a mapping between strings matching the pattern and their replacements
      replacementMap = {}

      # Reset the pattern's internal match tracker
      @options.pattern.lastIndex = 0

      # Search this file for strings that need replacing
      continue unless fs.existsSync(referenceFile)
      contents = fs.readFileSync(referenceFile).toString()
      match = @options.pattern.exec(contents)
      while match isnt null
        # Lookup the filename
        originalFilename = match[1]

        # Find a suitable replacement filename
        replacementFilename = renamedFiles[originalFilename]

        if @options.prependHost?[@config.env[0]]?
          replacementFilename = @options.prependHost[@config.env[0]] + replacementFilename

        # Synthesize the replacement
        replacementMap[if @options.discardNonFilenamePatternParts then match[0] else originalFilename] = replacementFilename or originalFilename

        # Search for the next match
        match = @options.pattern.exec(contents)

      # Perform the replacements
      for originalString, processedString of replacementMap
        findRegExp = new RegExp(@_escapeRegExp(originalString), 'g') # Add g flag for global replace
        contents = contents.replace(findRegExp, processedString)

      fs.writeFileSync(referenceFile, contents)

  _removeReferences: (files) ->
    return unless @options.discardNonFilenamePatternParts
    for file in files
      contents = fs.readFileSync(file).toString()
      contents = contents.replace(@options.pattern, '$1')
      fs.writeFileSync(file, contents)

module.exports = Digest
