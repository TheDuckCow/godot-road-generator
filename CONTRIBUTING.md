# How to contribute to this repository

## How to contribute

In all cases, it's best to communicate with the repository owners! If you are hoping to make a small change, direclty creating a pull request is a good option (but feel free to communicate via an issue ahead of time). For bigger changes that add whole new features or change funcitonality, it's better to discuss in an issue first to ensure there is alignment. 

The full process would thus be:

1. Open an issue which is a bug report or feature request, detail your proposal
1. Owners give the go ahead with any guidance
1. Create your branch/fork
    1. If you don't have edit access to the repo, then fork the enture project on github. If you have edit access, go to next sub bullet.
    1. If a `dev` branch exists, check it out; otheriwse, check out the `main` branch.
    1. Now create an appropriately named branch, add commits there
1. Crate a pull request, requesting to merge back into `main` (or into `dev` if that branch exists), and explicitly request review (add an owner)
1. Owners will review and likley give feedback. Don't be discouraged! But to get an edge, see the dev guidance below.
1. Author responds to comments, makes changes if appropriate. Go back one step to rereview
1. An owner approves, and indicates to the author if/when to merge
1. Author merges in the PR (owners may due this step if an approval is there and author is not responding)

## General guidance

- See [these high level requirements](https://docs.godotengine.org/en/stable/community/asset_library/submitting_to_assetlib.html) of a plugin in the Asset Library. Be sure to follow all of these.
- Follow the [official GDscript](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html) base code style
	- Owners will comment and request changes to ensure code style matches, so don't be surprised by this (or take offsense!)
- Generally try to additionally follow the [incremental style guide](https://www.gdquest.com/docs/guidelines/best-practices/godot-gdscript/) set forth by GDQuest, which adds several useful additional conventions.
- To reiterate a subset of what these code style guidelines indicate, you should:
	- Be using typing where possible (sometimes cyclic issues break this in 3.x)
	- Follow naming convention
	- More lines of code is ok if it makes what’s happening leaner

If in doubt, reach out to the owners by opening an issue. You can also join the Wheel Steal discord for more realtime engagement: discord.gg/gttJWznb4a
