class_name Hints
extends RefCounted
## The signposts' copy, from the web build's src/ui/hints.ts. Entries with three
## strings are device aware: keyboard, gamepad, touch.

const HINTS := {
	"move": ["Move with A and D, or the arrow keys", "Move with the left stick", "Drag on the left of the screen to move"],
	"jump": ["Space to jump. Hold it to jump higher", "A to jump. Hold it to jump higher", "Hold the round button to jump higher"],
	"depth": [
		"W and S walk towards the back and the front of the stage",
		"Push the stick up and down to walk in depth",
		"Drag up and down to walk in depth",
	],
	"switch2d": ["Press Shift to see the Score", "Press Y to see the Score", "Tap the page button to see the Score"],
	"switch3d": ["Press Shift to return to the Stage", "Press Y to return to the Stage", "Tap the stage button to return to the Stage"],
	"lineup": "On the page, whatever lines up is joined",
	"walkaround": "On the stage, walk round what blocks the page",
	"notes": "Seven notes are lost in every movement",
	"checkpoint": "Metronomes keep your place",
	"thorns": "On the page, thorns at every depth are in your way",
	"platform": "Music stands will carry you",
	"drum": "Land on a drum to leap high",
	"keys": "Piano keys raise and lower the golden bars",
	"discord": "Discords hum out of tune. On the page they stand at every depth",
	"midair": "You can turn the world in mid-air. It slows while it turns",
	"hidden": "Some notes hide behind things on the page",
	"exit": "The fermata closes the movement",
	"machine": "Some keys wake the machinery",
	"ride": "Behind the wall, the stage still carries you",
	"finale": "Everything you have learned, together",
}


static func text(id: String, device: String) -> String:
	var c = HINTS.get(id, "")
	if c is Array:
		var i := 0 if device == "keyboard" else (1 if device == "gamepad" else 2)
		return c[i]
	return c
