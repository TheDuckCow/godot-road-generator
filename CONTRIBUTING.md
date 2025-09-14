# How to contribute to this repository

## How to contribute

In all cases, it's best to communicate with the repository owners! If you are hoping to make a small change, directly creating a pull request is a good option (but feel free to communicate via an issue ahead of time). For bigger changes that add whole new features or change functionality, it's better to discuss in an issue first to ensure there is alignment. 

The full process would thus be:

1. Open an issue which is a bug report or feature request, detail your proposal
1. Owners give the go ahead with any guidance
1. Create your branch/fork
    1. If you don't have edit access to the repo, then fork the entire project on github. If you have edit access, go to next sub bullet.
    1. Base your changes off of the `dev` branch.
    1. Now create an appropriately named branch, add commits there
1. Run GUT tests to ensure everything is working as expected (nothing new broken)
    - These will also run automatically when a PR is opened, but best to check locally first
1. Create a pull request, requesting to merge back into `dev`, and explicitly request review (add an owner)
    - Best practice: Assign the relating issue to the pull request (or vice versa) in the GitHub UI on the righthand side, so it's clear what it relates to.
1. Owners will review and likely give feedback. Don't be discouraged! But to get an edge, see the dev guidance below.
1. Author responds to comments, makes changes if appropriate. Go back one step to re-review
    - To re-trigger the test runner on an existing PR, mark it as draft and switch back to review-ready; the runner does not run on every commit pushed.
1. An owner approves, and indicates to the author if/when to merge
1. Author merges in the PR (owners may do this step if an approval is there and author is not responding)

## How to run tests

In order to submit changes, all tests need to be passing. This repository uses the [bitwes/GUT framework](https://github.com/bitwes/Gut/) for this purpose.

Tests automatically run on GitHub via the workflow found in `.github/workflows/tests.yaml`. If your changes result in a test failure (red x), you should click on the details of that action run and then look into which test has failed.

Automated tests only run if:
- Changes are made to the `addon/road-generator` or `test` folders
- The PR is just opend or marked for review; tests do NOT run on each commit
  - To re-run tests for an already open PR, mark it as draft (top right on github) and then re-request review at the bottom

### Running tests locally

To run tests, you should see a "GUT" tab at the bottom of your main window to the right of Animation (if not, make sure the GUT plugin is enabled in project settings). Inside the GUT tab, you just need to `Run All` to run all tests.

You can also run tests from the command line (script set up for Linux/Max OSX):

1. Create a `godot_versions.txt` file in the root of the repo. This should not be checked in (already added to gitignores)
1. Create a single line with the path to the godot versions you want to use for testing. It should be the full path to the binary executable (not just the .app, for instance on OSX)
1. Then execute `run_tests.sh` and you should see test results in progress. As of this writing, Godot opens, tests run, and then godot closes all in less than 10 seconds.


## General guidance

- See [these high level requirements](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html) of a plugin in the Asset Library. Be sure to follow all of these.
- Follow the [official GDscript](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) base code style
	- Owners will comment and request changes to ensure code style matches, so don't be surprised by this (or take offense!)
- Generally try to additionally follow the [incremental style guide](https://www.gdquest.com/docs/guidelines/best-practices/godot-gdscript/) set forth by GDQuest, which adds several useful additional conventions.
- To reiterate a subset of what these code style guidelines indicate, you should:
	- Be using typing where possible
	- Follow naming convention
	- More lines of code is ok if it makes what is happening clearer.

If in doubt, reach out to the owners by opening an issue. You can also join the Wheel Steal discord for more realtime engagement: discord.gg/gttJWznb4a
