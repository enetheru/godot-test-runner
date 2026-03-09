## Left Side Test List
- [ ] Move the buttons to a third column, call it controls or something
- [ ] add in a countdown timer for the timout setting of a test
- [ ] Enable tests to register subtests and put them as sub items, with dependencies.
	- [ ] just requires a static function overload to trigger the specification on scan.
- [ ] button should have a debug re-run button.
- [ ] separate clear results from right side

## Right Side Test Output
- [ ] Make test element a foldable.
- [ ] double click to open test script
- [ ] clear succeeded
- [ ] filter
- [ ] diff two outputs
- [ ] rerun failed

## OutputBox
- [ ] Put controls inside the box
	- [ ] re-run
	- [ ] clear others
- [ ] Add field in the test for changing the title.
- [ ] option to enable bbcode?
## Controls
- [ ] It appears that filters, and folder do not mean anything.
- [ ] icons in the middle are not readable I think that perhaps i can make a background tricolour fill for untested/good/bad
- [ ] nothing has tooltips
- [ ] Help Button shows nothing.
- [ ] Add a stop button somewhere for long running tests.

## Other
- [ ] Project based settings would be nice
- [ ] Robust example folder to showcase the features
- [ ] threaded file loading
- [ ] Test detection is currently based on "test_" file prefix, when I could just as easily load and test the type against `TestBase`
- [ ] runcode is an enum, but that limits the possibilities, change it to an int.
