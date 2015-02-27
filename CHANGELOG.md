# v1.5.1

* Bug fix: don't add -null to urls that do not resolve to a file.
* Resolve relative urls including '..' to absolute paths.

# v1.5.0

* Refactor to compute digests in dependency order.
  This change lets you digest html and css together with changing binary assets.
* Added Digest.logger for logging to arbitrary routers.
* This library will now be loaded as a coffee script,
  instead of adding the intermediate compilation step to js.

# v1.4.2

* Refactored fake-fs tests to use the real file system.
  The fake-fs was somehow causing mocha
  to report process success even on test failure.
* Removed the compilation to javascript step.
  This happens with node and coffeescript automatically.
* Added Digest.logger for overriding the default `console` logger.

# v1.4.1

* Updated all dependencies; this made all failing tests pass

# v1.4.0

* Feature: [add infix version of file with same digest as original][17]

# v1.3.0

* Feature: [Option to output digest manifest to JSON file][15]

# v1.2.2

* Fix: [issue with repeated DIGEST occurrences not being replaced][11]

# v1.2.1

* Chore: Compile JavaScript.

# v1.2.0

* Feature: [Environment-specific host][10] thanks to @Tomtomgo.

# v1.1.1

* Fix: Compile JavaScript.

# v1.1.0

* Customizable DIGEST pattern (thanks to @steveluscher)

# v1.0.6

* Handle missing files gracefully.

# v1.0.5

* Allow for leading `/` in DIGEST filenames.

# v1.0.4

* Warning in dynamic mode.

# v1.0.3

* Fix typo in warning message for precision.

# v1.0.2

* Forgot to compile the JS.

# v1.0.1

* Remove DIGEST references when digest-brunch not run.

# v1.0.0

* Initial release


[10]: https://github.com/mutewinter/digest-brunch/pull/10
[11]: https://github.com/mutewinter/digest-brunch/issues/11
[15]: https://github.com/mutewinter/digest-brunch/pull/15
[17]: https://github.com/mutewinter/digest-brunch/pull/17
