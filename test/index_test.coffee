FakeFs = require 'fake-fs'
realFs = require 'fs'
path = require 'path'
fs = new FakeFs

FIXTURES_AND_DIGESTS =
  'index.html': 1
  'undigested.js': 1
  'test.js': 'test-75570c26.js'
  'js/nested.js': 'js/nested-4df52a0a.js'
  'test.css': 'test-e3eda643.css'

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

  it 'is an object', ->
    expect(typeof digest).to.eq('object')

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

    it 'replaces occurrences of test.css in index.html', ->
      expect(fs.readFileSync('public/index.html').toString()).to.contain(
        relativeDigestFilename('test.css')
      )

    it 'replaces occurrences of js/nested.js in index.html', ->
      expect(fs.readFileSync('public/index.html').toString()).to.contain(
        relativeDigestFilename('js/nested.js')
      )

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

    it 'does run with alwaysRun flag set', ->
      digest.options.alwaysRun = true
      digest.onCompile()
      expect(fs.existsSync(digestFilename('test.js'))).to.be.true
