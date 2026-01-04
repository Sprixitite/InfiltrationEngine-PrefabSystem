<a name="top-of-entry"></a>

# Demystifying Prefabs // Part 0.5: Background
## Previous Entry: [Part 0.0: Documentation Usage](./0_0_StartHere.md)
##     Next Entry: [Part 1.0: The Basics](./1_0_Basics.md)

# Subject
This entry is an explanation as to the goals of, and motivation behind the plugin.
Should you not be interested, move onto the next chapter.

# Content
If you're reading this, I'm assuming you're sticking around for the page, thanks. I appreciate your interest.

This plugin was initially a concept brought up in passing by Roliuu, creator of The Exchange. I immediately loved the idea and roughed-out the same prefab layout that is still in-use in this current version (granted, with a *lot* more extensions).

The plugin aims to further "democratize" the engine by allowing users to author their own self-contained objects featuring unique logic, in a similar way to how Morgan can author self-contained Props with custom scripted behaviour. While the workflow will never be *as* ideal as scripting everything in Lua, basic logic can easily be expressed via Mission Globals, and complex logic may still be bundled via StateScripts.

The simple ability to create custom reusable assets is indispensible and the lack of such an ability native to the engine adds a sort of "Configuration Overhead" to community mission developers every time they wish to duplicate a custom setup, with this cost scaling depending on the complexity of the setup. I found this to not only be tedious but also substantially limit reasonable mission scope, as well as being a significant source of bugs.

Prefabs aim to remedy this by allowing for the authoring and redistribution of self-contained Prefabs (collections of standard mission assets) without any actual engine support. This is done by using the Serializer's Cross-Plugin API to boil every prefab down into regular ole' mission assets before the map gets saved out.

Due to how the system functions, there is no code-size overhead when using Prefabs instead of manually wiring everything up yourself.

I've written a lot of code for this Plugin, most of which hasn't ever seen the light of day! I'm writing these docs with the hope that people other than me can begin to familiarise themselves with the Prefab workflow, as I feel it would be a shame to see all my effort go to waste, and would love to be able to remove barriers on scope for community missions.

## Video Series?
Initially, the first entry in this series (1.0: The Basics) was written in the format of a vocal script for a YouTube video - this was done partly because I found it easier to write, and partly because I would quite like making this a video series, were it to make things more accessible.

Unfortunately I am not willing to split my free time further to try and make this happen, and I absolutely despise the process of video editing, so these will likely remain text documents, at least for the foreseeable future.

# Sign-Off
My blabbering aside, I've nothing more to put here.

You should continue to the next entry, **[The Basics](./1_0_Basics.md)**.
<sub>

[Click To Jump To Top](#top-of-entry)
</sub>