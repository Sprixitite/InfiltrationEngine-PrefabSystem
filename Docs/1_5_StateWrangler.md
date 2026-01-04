# Demystifying Prefabs // Part 1½: StateWrangler
## Previous Entry: [1.0: The Basics](./1_0_Basics.md)
##     Next Entry: [2.0: Advanced Attributes](./2_0_AdvancedAttributes.md)

> [!CAUTION]
> This entry is currently in a very early state, rely on it with caution

## Intro
Okay hi welcome to episode 1½, more of a sidequest than a full entry but I didn't know where else to put this.

Feel free to skip this, but consider coming back later to make sure you're aware of this, as StateWrangler can be quite useful!

## StateWrangler
StateWrangler is a plugin allowing for the usage of a new folder in your mission - the **MissionGlobals** folder.

Available both in standalone form as well as bundled with newer versions of PrefabSystem - StateWrangler allows you to insert variables into your MissionSetup before export.
This can be used in Prefabs, for when you need some variables per-prefab-instance.

Any [StringValue](https://create.roblox.com/docs/reference/engine/classes/StringValue)s placed inside of the `MissionGlobals` folder before export will be placed into the Globals table by default, with their Name as the Key and their Value as the Value

If a "Destination" attribute is found on a StringValue, the table to which the value is sent will change - this can let you add strings in a much more user-friendly way, by exposing the string itself as a Prefab setting and handling setting up the string inside of the prefab.