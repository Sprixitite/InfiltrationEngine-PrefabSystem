# Demystifying Prefabs // The Basics

## Intro
Hi hello welcome to this (hopefully quite short) series on InfiltrationEngine PrefabSystem - This is the "Episode 1" of sorts

Just before you we start, you are expected to understand the concepts listed here, the super important ones being
- Roblox Instances
- Instance Attributes
- Instance Properties
- The difference between attributes and properties
- The rough layout and innerworkings of custom missions

The aforementioned info will be vital to your understanding of the plugin and how it aims to aid in mission development, if you don't already understand how studio or missions themselves tick, this series doesn't aim to be a tutorial for either and will be significantly less useful to you - sorry

I do have a preamble here but I'll flash up a timestamp on screen and throw it in the description if you don't want to listen to my little introduction to the plugin and this series, thanks

## Preamble
So for those of you sticking around for the preamble, thanks, I appreciate your interest in what I have to say and I'll try to keep it nice and brief

To give an overview of the aims of what will hopefully turn into a small video series - I've seen a lot of people interested in custom missions are rightfully very confused with what a prefab is and how to use them, and this video aims to be a sort of high-level documentation from myself to the community such that hopefully more people can understand them, because I really don't want my effort on this plugin and the accompanying SerializerAPI to go to waste. I am not a content creator by any means and actually quite despise the process of editing videos - do not expect this series to be flashy in that respect - but I would never get any of this information out in a digestible and approachable format if I decided to write a large document or try and make my own video editor

And, to give a brief introduction to prefab system and it's goals, PrefabSystem is a plugin developed by myself to allow for a workflow similar to one you might find in a better engine than Roblox Studio, whereby you can bundle collections of game assets together into one "Prefab", with some parameters given to customise how the contents of the prefab behave in one convenient place. Although there is definitely more time investment in creating complicated prefabs, you can likely imagine the incredible efficiency gains when it comes to re-using assets.

To give just one practical example, imagine you need to create your own custom disguise point using a disguise trigger and a custom prop, with each of these custom disguise points being one-time use, instead of manually copy-pasting each disguise trigger & prop all over your map, and then manually adjusting the output variables on everything every time, and debugging any mistakes you might have made, you can make one prefab, give it only the settings that you actually need, then copy & paste THAT all over your mission, adjusting many fewer settings and dealing with many fewer instances - you can even automatically generate the output variables if they're only used inside of your prefab!

This was an idea brought up to me by Roliuu, creator of the very good loud mission - even if she won't admit it - The Exchange, and immediately upon hearing of it it stuck with me until my eventually making the Serializer API and subsequently the plugin

All my marketing points out of the way, I'll let you get to what you're actually here for

## The Basics
At a high level, simple prefabs look like the image shown on screen. Prefabs are unpacked into regular mission elements when exporting

They're composed of a couple things, internally the plugin breaks these down into:
- Prefab Scopes
- Scope Targets
- Scope Target Outputs  
and a final category I decided to call
- ✨ Special ✨ Scope Instances

Scope Targets & Their Outputs are very easy to explain, each Scope Target is a folder inside of a Prefab Scope, the folder name name corresponding with the name of a folder in your mission. Anything inside a target folder is output to the corresponding mission folder.

Special Scope Instances are non-folder instances belonging to the top level of a Prefab Scope, any Instance derived from [ValueBase](https://create.roblox.com/docs/reference/engine/classes/ValueBase) is a valid Special Scope Instance in every scope, but otherwise this differs per-scope

The most important Special Scope Instance is the InstanceBase part in the Instance scope, which we'll look at more later

Prefab Scopes are a little more complicated but are very important. Prefab Scopes should always be the folders right at the top of your prefab, there are currently three valid scopes:
- Instance
- Static
- Remote (also known as Extern or Area)

### Remote Scope Overview
This scope is *extremely* niche and advanced, so we'll ignore it in this entry and probably for the rest of the series

**Instance** & **Static** are much simpler and more common.

### Instance Scope Overview
Any Scope Targets found within the Instance scope will be output one time for every "Instantiation" of a prop

"Instantiation" is a word I will use a lot in this series and it just means a "Usage" of the Prefab, i.e. if you place two copies of a prefab you have "Instantiated" it twice - this means if there are two instances of your prefab, there will be two copies of everything in the prefab's Instance Scope. 

We'll come back to the instance scope later, as it's very closely tied to a Special "InstanceBase" Scope Instance you may have noticed earlier, and is where most of your prefabs' elements will end up.

### Static Scope Overview 
With regards to the Static scope, any Scope Targets within it will be output one time to the mission as-is, regardless of whether the prefab is used or not.

For example, if you have a Prefab where every Instance will re-use the same Custom Prop, putting that Custom Prop in the Static scope will make sure each instance of the prefab doesn't create its own version of it. This is practical for bundling required assets with your prefab so you can share it.

## The Instance Scope
Circling back to the Instance Scope and the mysterious little InstanceBase part from earlier, this is what makes the Instance scope tick. 

The InstanceBase is basically a Custom Prop base on steroids. Each attributes' name is a setting on the Prefab, and each attributes' value on the InstanceBase is the default value for that setting.

In addition to configuring your Prefab's attributes, the InstanceBase also positions outputs of the Instance Scope relative to itself.

The InstanceBase never actually makes it into your mission, and is deleted before the map is exported.

## Attributes
As you should hopefully know, the main way of configuring gameplay elements in the InfiltrationEngine is via their Attributes - PrefabSystem keeps with this flow, but allows you to insert variables into whatever attributes you like before they're put into your mission.

When exporting, attributes on items in a prefab undergo evaluation - this is what I'm referring to when I mention "Attribute Evaluation"

During attribute evaluation, all string attributes go through a process where their value is edited/replaced

Settings from your InstanceBase may be inserted into an attribute by placing the setting name in brackets, prefixed with a dollar sign, like so: `$(SettingName)`

If an attribute is composed of nothing but a single substitution, the attribute will be set to the value of the

Conversely if the substitution is apart of a string then the value is inserted into the string.

The contents of the brackets may be just a setting in this case, but it is actually a very simple attribute expression, we'll go into more detail about these in another entry but you should keep this terminology in mind and keep aware that they are capable of much more than basic substitution.

## Attribute Modifiers
Attributes are not as simple as they appear, with their names being able to contain modifiers in the format of
`priority.scope.target`
where priority and scope are both optional.

Priority is self explanatory, attributes beginning with lower numbers will be evaluated before those with higher numbers. All attributes with a priority will run before those without a priority, those without a priority will run in alphabetical order but this shouldn't be relied upon.

A special-case is any given instance's name, which also undergoes attribute evaluation after every attribute.

Similarly to prefabs themselves, attributes within prefabs may also belong to "scopes" of their own. As of writing there are 5, belonging to two different types:

There are the import scopes:
- imponly
- noimp
And the standard scopes:
- peval
- ignore
- this

Import scopes are only for use on the InstanceBase, whereas standard scopes are only for use on Scope Target Outputs, use outside of these guidelines may technically function but is not officially supported and may break in future.

The import scopes determine how attribute defaults work with SpongeZoneTools' attribute importer, and won't be touched on further here.

The standard scopes are much more interesting.

The `peval` scope is complicated enough it will likely need it's own entry in this series of documentation.

The `ignore` scope is useful in conjunction with some more advanced features/concepts, any attribute in this scope will be deleted following its evaluation.

The `this` scope will set the corresponding property on whichever instance it belongs to, for example: the `this.Position` attribute will set the Instance's position.

## Outro
I hope this has been helpful as a resource, and that you can muster tuning into the Advanced Attributes follow-up that I hopefully make happen, where we'll cover GizFuncs (formerly known as SFuncs), ShebangScripts, advanced attribute substitution expressions, and the `peval` attribute scope