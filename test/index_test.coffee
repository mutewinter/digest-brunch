Digest = require('../src/index')
expect = require('chai').expect
fs = require 'fs'
fse = require 'fs-extra'
path = require 'path'

Digest.logger = {
  warn: (message) -> null # do nothing
}

FIXTURES_AND_DIGESTS =
  'test.js': 'test-75570c26.js'
  'js/nested.js': 'js/nested-4df52a0a.js'
  'test.css': 'test-e3eda643.css'
  'otter.jpeg': 'otter-ea06c477.jpeg'
  'otter-style.css': 'otter-style-8b2b0bb8.css'

digestFilename = (filename) ->
  digest = FIXTURES_AND_DIGESTS[filename] || filename
  path.posix.join(__dirname, 'public', digest)

digestFileExists = (filename) ->
  fs.existsSync(digestFilename(filename))

readDigestFile = (filename) ->
  fs.readFileSync(digestFilename(filename), 'UTF-8')

relativeDigestFilename = (filename) ->
  path.posix.relative(path.posix.join(__dirname, 'public'), digestFilename(filename))

loadFixture = (from, to = from) ->
  realContents = realFs.readFileSync("test/fixtures/#{from}").toString()
  fs.file("public/#{to}", realContents)

setupFakeFileSystem = ->
  fse.removeSync path.join(__dirname, 'public')
  fse.copySync path.join(__dirname, 'fixtures'), path.join(__dirname, 'public')

describe 'Digest', ->
  digest = null

  beforeEach ->
    digest = new Digest(
      env: ['production']
      paths:
        public: path.join('test', 'public')
      plugins:
        digest:
          referenceFiles: /\.(html|css)$/
    )

  after ->
    fse.removeSync path.join(__dirname, 'public')

  it 'is an instance of Digest', ->
    expect(digest).to.be.instanceOf(Digest)

  it 'has default config keys', ->
    expect(digest.options).to.include.keys('precision', 'referenceFiles')

  describe 'regular compile', ->
    beforeEach ->
      setupFakeFileSystem()
      digest.onCompile()

    it 'renames test.js with digest', ->
      expect(digestFileExists('test.js')).to.be.true

    it 'renames test.css with digest', ->
      expect(digestFileExists('test.css')).to.be.true

    it 'renames js/nested.js with digest', ->
      expect(digestFileExists('js/nested.js')).to.be.true

    it 'does not rename files not present in any html file', ->
      expect(digestFileExists('undigested.js')).to.be.true

    it 'replaces occurrences of test.js in index.html', ->
      expect(readDigestFile('index.html')).to.contain(
        relativeDigestFilename('test.js')
      )

    it 'replaces ALL occurrences of test.js in index.html', ->
      expect(readDigestFile('index.html')).to.not.contain 'test.js'

    it 'replaces occurrences of test.css in index.html', ->
      expect(readDigestFile('index.html')).to.contain(
        relativeDigestFilename('test.css')
      )

    it 'replaces occurrences of js/nested.js in index.html', ->
      expect(readDigestFile('index.html')).to.contain(
        relativeDigestFilename('js/nested.js')
      )

    it 'cascades digest dependencies', ->
      expect(readDigestFile('otter-style.css')).to.contain(
        relativeDigestFilename('otter.jpeg')
      )
      expect(readDigestFile('otter-page.html')).to.contain(
        relativeDigestFilename('otter-style.css')
      )

    it 'replaces relative digest urls', ->
      expect(readDigestFile('css/relative.css')).to.contain(
        path.posix.join('..', relativeDigestFilename('otter.jpeg'))
      )

  describe 'asset host prepending', ->
    beforeEach ->
      setupFakeFileSystem()

    it 'prepends alternative asset host when set for env', ->
      host = 'http://wow_such_host.com'
      digest.options.prependHost = {test: host}
      digest.config.env = ['test']
      digest.options.environments = ['test']
      digest.onCompile()
      expect(readDigestFile('index.html')).to.contain(host)

    it 'does not prepend alternative asset host when not set for env', ->
      host = 'http://wow_such_host.com'
      digest.options.prependHost = {no_test: host}
      digest.config.env = ['test']
      digest.options.environments = ['test']
      digest.onCompile()
      expect(readDigestFile('index.html')).to.not.contain(host)

  describe 'alternate file versions with infixes', ->
    beforeEach ->
      setupFakeFileSystem()

    it 'copies digest to alternative file', ->
      digest.options.infixes = ["@2x"]
      digest.onCompile()
      original = relativeDigestFilename('otter.jpeg')
      splitPos = original.length - 5 # we insert the @2x just before the .jpeg
      infixDigested = [original.slice(0, splitPos), "@2x", original.slice(splitPos)].join("")
      expect(fs.existsSync(path.join(__dirname, 'public', infixDigested))).to.be.ok

    it 'does not copy digest to alternative file if not requested', ->
      digest.options.infixes = []
      digest.onCompile()
      original = relativeDigestFilename('otter.jpeg')
      splitPos = original.length - 5 # we insert the @2x just before the .jpeg
      infixDigested = [original.slice(0, splitPos), "@2x", original.slice(splitPos)].join("")
      expect(fs.existsSync(path.join(__dirname, 'public', infixDigested))).to.be.not.ok
      expect(fs.existsSync(path.join(__dirname, 'public', 'otter@2x.jpeg'))).to.be.ok

  describe 'two digests on one line', ->
    beforeEach ->
      setupFakeFileSystem()
      digest.onCompile()

    it 'replaces both digests', ->
      contents = readDigestFile('two_per_line.html')
      expect(contents).to.contain(relativeDigestFilename('test.js'))
      expect(contents).to.contain(relativeDigestFilename('js/nested.js'))

  describe 'no digests in a file', ->
    beforeEach ->
      setupFakeFileSystem()
      @originalContents = readDigestFile('no_digests.html')
      digest.onCompile()

    it 'does not change the file', ->
      expect(@originalContents).to.eq(
        readDigestFile('no_digests.html')
      )

  describe 'two html files', ->
    beforeEach ->
      setupFakeFileSystem()
      fse.copySync(__dirname + '/public/index.html', __dirname + '/public/second.html')
      digest.onCompile()

    it 'replaces occurrences of test.js in both files', ->
      expect(readDigestFile('second.html')).to.contain(
        relativeDigestFilename('test.js')
      )
      expect(readDigestFile('index.html')).to.contain(
        relativeDigestFilename('test.js')
      )

  describe 'precision', ->
    beforeEach ->
      setupFakeFileSystem()
      digest.options.precision = 6
      digest.onCompile()

    it 'renames test.js with desired digest precision', ->
      expect(digestFileExists('test-75570c.js')).to.be.true

    it 'inserts reference to digested file with desired precision', ->
      expect(readDigestFile('index.html')).to.contain(
        'test-75570c.js'
      )

  describe 'environment detection', ->
    beforeEach ->
      setupFakeFileSystem()

    it 'does not run in non-production environment', ->
      digest.config.env = []
      digest.onCompile()
      expect(digestFileExists('test.js')).to.be.false

    it 'does run in selected non-production environment', ->
      digest.options.environments = ['amazing_super']
      digest.config.env = ['amazing_super']
      digest.onCompile()
      expect(digestFileExists('test.js')).to.be.true

    it 'does not run in not selected non-production environment', ->
      digest.options.environments = ['amazing_super']
      digest.config.env = ['boring_super']
      digest.onCompile()
      expect(digestFileExists('test.js')).to.be.false

    it 'does run with alwaysRun flag set', ->
      digest.options.alwaysRun = true
      digest.onCompile()
      expect(digestFileExists('test.js')).to.be.true

  describe 'when not run', ->
    beforeEach ->
      setupFakeFileSystem()
      digest = new Digest(
        env: []
        paths:
          public: path.join('test', 'public')
      )


    it 'reverts matched patterns', ->
      digest.onCompile()
      contents = readDigestFile('index.html')
      expect(contents).to.not.contain('DIGEST')

    it 'reverts two matched patterns on the same line', ->
      digest.onCompile()
      contents = readDigestFile('two_per_line.html')
      expect(contents).to.not.contain('DIGEST')
      expect(contents).to.contain('test.js')
      expect(contents).to.contain('js/nested.js')

  # Regression test for https://github.com/mutewinter/digest-brunch/issues/2
  describe 'leading slash', ->
    beforeEach ->
      setupFakeFileSystem()
      digest.onCompile()

    it 'replaces occurrences of /test.js', ->
      expect(readDigestFile('leading_slash.html')).
        to.contain("/#{relativeDigestFilename('test.js')}")

  describe 'missing file referenced', ->
    beforeEach ->
      setupFakeFileSystem()

    it 'does not crash', ->
      expect(digest.onCompile.bind(digest)).to.not.throw(Error)

    it 'removes the digest from missing references', ->
      digest.onCompile()
      expect(readDigestFile('missing_reference.html')).
        to.contain('"missing_file.js"')

    it 'still replaces valid references', ->
      digest.onCompile()
      expect(readDigestFile('missing_reference.html')).
        to.contain(relativeDigestFilename('test.css'))

  describe 'pattern', ->

    describe 'discarded', ->

      beforeEach ->
        setupFakeFileSystem()
        digest.options.referenceFiles = /\.alt1$/
        digest.options.pattern = /\*+([^\*]+)\*+/g
        digest.options.discardNonFilenamePatternParts = yes
        digest.onCompile()
        @contents = readDigestFile('alternate_pattern.html.alt1')

      it 'discards the non-filename parts of the pattern', ->
        contents = readDigestFile('alternate_pattern.html.alt1')
        expect(contents).to.not.contain('"**')
        expect(contents).to.not.contain('**"')
        expect(contents).to.not.contain('"***')
        expect(contents).to.not.contain('***"')
        expect(contents).to.not.contain('"****')
        expect(contents).to.not.contain('****"')

      it 'replaces occurrences of test.js in alternate_pattern.html.alt1', ->
        expect(@contents).to.contain relativeDigestFilename('test.js')

      it 'replaces occurrences of test.css in alternate_pattern.html.alt1', ->
        expect(@contents).to.contain relativeDigestFilename('test.css')

      it 'replaces occurrences of js/nested.js in alternate_pattern.html.alt1', ->
        expect(@contents).to.contain relativeDigestFilename('js/nested.js')

    describe 'non-discarded', ->

      beforeEach ->
        setupFakeFileSystem()
        digest.options.referenceFiles = /\.alt2$/
        digest.options.pattern = /['"]([^'"]+)['"]/g
        digest.options.discardNonFilenamePatternParts = no
        digest.onCompile()
        @contents = readDigestFile('alternate_pattern_no_discard.html.alt2')

      it 'replaces occurrences of test.js in alternate_pattern_no_discard.html.alt2', ->
        expect(@contents).to.contain "\"#{relativeDigestFilename('test.js')}\""

      it 'replaces occurrences of test.css in alternate_pattern_no_discard.html.alt2', ->
        expect(@contents).to.contain "'#{relativeDigestFilename('test.css')}'"

      it 'replaces occurrences of js/nested.js in alternate_pattern_no_discard.html.alt2', ->
        expect(@contents).to.contain "\"#{relativeDigestFilename('js/nested.js')}\""

  describe 'manifest', ->
    beforeEach ->
      setupFakeFileSystem()

    it 'outputs a manifest', ->
      digest.options.manifest = 'test/public/manifest.json'
      digest.onCompile()
      manifest = JSON.parse(readDigestFile('manifest.json'))
      expect(Object.keys(manifest)).to.have.length Object.keys(FIXTURES_AND_DIGESTS).length
      for url of FIXTURES_AND_DIGESTS
        expect(manifest[url]).to.equal FIXTURES_AND_DIGESTS[url]

  describe 'circular dependency', ->
    beforeEach ->
      setupFakeFileSystem()
      digest = new Digest(
        env: ['production']
        paths:
          public: path.join('test', 'public')
        plugins:
          digest:
            referenceFiles: /\.circle$/
      )

    it 'throws', ->
      expect(-> digest.onCompile()).to.throw('circular1.circle')
