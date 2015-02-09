Digest = require('../src/index')
expect = require('chai').expect
FakeFs = require 'fake-fs'
realFs = require 'fs'
path = require 'path'
fs = new FakeFs

FIXTURES_AND_DIGESTS =
  'index.html': 1
  'alternate_pattern.html.alt1': 1
  'alternate_pattern_no_discard.html.alt2': 1
  'undigested.js': 1
  'test.js': 'test-75570c26.js'
  'js/nested.js': 'js/nested-4df52a0a.js'
  'test.css': 'test-e3eda643.css'
  'otter.jpeg': 'otter-b7071245.jpeg'

digestFilename = (filename) ->
  path.join('public', FIXTURES_AND_DIGESTS[filename])

relativeDigestFilename = (filename) ->
  path.relative('public', digestFilename(filename))

loadFixture = (from, to = from) ->
  realContents = realFs.readFileSync("test/fixtures/#{from}").toString()
  fs.file("public/#{to}", realContents)

setupFakeFileSystem = ->
  fs.unpatch()
  # Make a new file system every time
  fs = new FakeFs
  for filename of FIXTURES_AND_DIGESTS
    loadFixture(filename)
  fs.patch()

describe 'Digest', ->
  digest = null

  beforeEach ->
    digest = new Digest(
      env: ['production']
      paths: public: 'public'
    )

  it 'is an instance of Digest', ->
    expect(digest).to.be.instanceOf(Digest)

  it 'has default config keys', ->
    expect(digest.options).to.include.keys('precision', 'referenceFiles')

  describe 'regular compile', ->
    beforeEach ->
      setupFakeFileSystem()
      digest.onCompile()

    it 'renames test.js with digest', ->
      expect(fs.existsSync(digestFilename('test.js'))).to.be.true

    it 'renames test.css with digest', ->
      expect(fs.existsSync(digestFilename('test.css'))).to.be.true

    it 'renames js/nested.js with digest', ->
      expect(fs.existsSync(digestFilename('js/nested.js'))).to.be.true

    it 'does not rename files not present in any html file', ->
      expect(fs.existsSync('public/undigested.js')).to.be.true

    it 'replaces occurrences of test.js in index.html', ->
      expect(fs.readFileSync('public/index.html').toString()).to.contain(
        relativeDigestFilename('test.js')
      )

    it 'replaces ALL occurrences of test.js in index.html', ->
      expect(fs.readFileSync('public/index.html').toString()).to.not.contain 'test.js'

    it 'replaces occurrences of test.css in index.html', ->
      expect(fs.readFileSync('public/index.html').toString()).to.contain(
        relativeDigestFilename('test.css')
      )

    it 'replaces occurrences of js/nested.js in index.html', ->
      expect(fs.readFileSync('public/index.html').toString()).to.contain(
        relativeDigestFilename('js/nested.js')
      )

  describe 'asset host prepending', ->
    beforeEach ->
      setupFakeFileSystem()
      digest = new Digest(env: [], paths: public: 'public')

    it 'prepends alternative asset host when set for env', ->
      host = 'http://wow_such_host.com'
      digest.options.prependHost = {test: host}
      digest.config.env = ['test']
      digest.options.environments = ['test']
      digest.onCompile()
      expect(fs.readFileSync('public/index.html').toString()).to.contain(host)

    it 'does not prepend alternative asset host when not set for env', ->
      host = 'http://wow_such_host.com'
      digest.options.prependHost = {no_test: host}
      digest.config.env = ['test']
      digest.options.environments = ['test']
      digest.onCompile()
      expect(fs.readFileSync('public/index.html').toString()).to.not.contain(host)

  describe.skip 'alternate file versions with infixes', ->
    beforeEach ->
      setupFakeFileSystem()
      digest = new Digest(env: [], paths: public: 'public')

    it 'copies digest to alternative file', ->
      digest.options.infixes = ["@2x"]
      digest.onCompile()
      original = relativeDigestFilename('otter.jpeg')
      splitPos = original.length - 5 # we insert the @2x just before the .jpeg
      infixDigested = [original.slice(0, splitPos), "@2x", original.slice(splitPos)].join("")
      expect(fs.existsSync(path.join('public', infixDigested))).to.be.ok

    it 'does not copy digest to alternative file if not requested', ->
      digest.options.infixes = null
      digest.onCompile()
      original = relativeDigestFilename('otter.jpeg')
      splitPos = original.length - 5 # we insert the @2x just before the .jpeg
      infixDigested = [original.slice(0, splitPos), "@2x", original.slice(splitPos)].join("")
      expect(fs.existsSync(path.join('public', infixDigested))).to.be.not.ok

  describe 'two digests on one line', ->
    beforeEach ->
      setupFakeFileSystem()
      fs.unpatch()
      loadFixture('two_per_line.html')
      fs.patch()
      digest.onCompile()

    it 'replaces both digests', ->
      contents = fs.readFileSync('public/two_per_line.html').toString()
      expect(contents).to.contain(relativeDigestFilename('test.js'))
      expect(contents).to.contain(relativeDigestFilename('js/nested.js'))

  describe 'no digests in a file', ->
    beforeEach ->
      setupFakeFileSystem()
      fs.unpatch()
      loadFixture('no_digests.html')
      fs.patch()
      @originalContents = fs.readFileSync('public/no_digests.html').toString()
      digest.onCompile()

    it 'does not change the file', ->
      expect(@originalContents).to.eq(
        fs.readFileSync('public/no_digests.html').toString()
      )

  describe 'two html files', ->
    beforeEach ->
      setupFakeFileSystem()
      fs.unpatch()
      loadFixture('index.html', 'second.html')
      fs.patch()
      digest.onCompile()

    it 'replaces occurrences of test.js in both files', ->
      expect(fs.readFileSync('public/second.html').toString()).to.contain(
        relativeDigestFilename('test.js')
      )
      expect(fs.readFileSync('public/index.html').toString()).to.contain(
        relativeDigestFilename('test.js')
      )

  describe 'precision', ->
    beforeEach ->
      setupFakeFileSystem()
      digest.options.precision = 6
      digest.onCompile()

    it 'renames test.js with desired digest precision', ->
      expect(fs.existsSync('public/test-75570c.js')).to.be.true

    it 'inserts reference to digested file with desired precision', ->
      expect(fs.readFileSync('public/index.html').toString()).to.contain(
        'test-75570c.js'
      )

  describe 'environment detection', ->
    beforeEach ->
      setupFakeFileSystem()
      digest = new Digest(env: [], paths: public: 'public')

    it 'does not run in non-production environment', ->
      digest.config.env = []
      digest.onCompile()
      expect(fs.existsSync(digestFilename('test.js'))).to.be.false

    it 'does run in selected non-production environment', ->
      digest.options.environments = ['amazing_super']
      digest.config.env = ['amazing_super']
      digest.onCompile()
      expect(fs.existsSync(digestFilename('test.js'))).to.be.true

    it 'does not run in not selected non-production environment', ->
      digest.options.environments = ['amazing_super']
      digest.config.env = ['boring_super']
      digest.onCompile()
      expect(fs.existsSync(digestFilename('test.js'))).to.be.false

    it 'does run with alwaysRun flag set', ->
      digest.options.alwaysRun = true
      digest.onCompile()
      expect(fs.existsSync(digestFilename('test.js'))).to.be.true

  describe 'when not run', ->
    beforeEach ->
      setupFakeFileSystem()
      digest = new Digest(env: [], paths: public: 'public')

    it 'reverts matched patterns', ->
      digest.onCompile()
      contents = fs.readFileSync('public/index.html').toString()
      expect(contents).to.not.contain('DIGEST')

    it 'reverts two matched patterns on the same line', ->
      fs.unpatch()
      loadFixture('two_per_line.html')
      fs.patch()
      digest.onCompile()
      contents = fs.readFileSync('public/two_per_line.html').toString()
      expect(contents).to.not.contain('DIGEST')
      expect(contents).to.contain('test.js')
      expect(contents).to.contain('js/nested.js')

  # Regression test for https://github.com/mutewinter/digest-brunch/issues/2
  describe 'leading slash', ->
    beforeEach ->
      setupFakeFileSystem()
      fs.unpatch()
      loadFixture('leading_slash.html')
      fs.patch()
      digest.onCompile()

    it 'replaces occurrences of /test.js', ->
      expect(fs.readFileSync('public/leading_slash.html').toString()).
        to.contain("/#{relativeDigestFilename('test.js')}")

  describe 'missing file referenced', ->
    beforeEach ->
      setupFakeFileSystem()
      fs.unpatch()
      loadFixture('missing_reference.html')
      fs.patch()

    it 'does not crash', ->
      expect(digest.onCompile.bind(digest)).to.not.throw(Error)

    it 'still replaces valid references', ->
      digest.onCompile()
      expect(fs.readFileSync('public/missing_reference.html').toString()).
        to.contain(relativeDigestFilename('test.css'))

  describe 'pattern', ->

    describe 'discarded', ->

      beforeEach ->
        setupFakeFileSystem()
        digest.options.referenceFiles = /\.alt1$/
        digest.options.pattern = /\*+([^\*]+)\*+/g
        digest.options.discardNonFilenamePatternParts = yes
        digest.onCompile()
        @contents = fs.readFileSync('public/alternate_pattern.html.alt1').toString()

      it 'discards the non-filename parts of the pattern', ->
        contents = fs.readFileSync('public/alternate_pattern.html.alt1').toString()
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
        @contents = fs.readFileSync('public/alternate_pattern_no_discard.html.alt2').toString()

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
      digest.options.manifest = 'public/manifest.json'
      digest.onCompile()
      manifest = JSON.parse(fs.readFileSync('public/manifest.json'))
      expect(Object.keys(manifest)).to.have.length 4
      expect(manifest['test.js']).to.equal FIXTURES_AND_DIGESTS['test.js']
      expect(manifest['js/nested.js']).to.equal FIXTURES_AND_DIGESTS['js/nested.js']
      expect(manifest['test.css']).to.equal FIXTURES_AND_DIGESTS['test.css']
