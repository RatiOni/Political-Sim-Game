extends Node

## Autoload. Set by the main menu before switching to the campaign scene;
## App reads it once in _ready() to decide whether to start fresh or load
## the client's own save. Defaults to "new" so loading main.tscn directly
## (the headless scene test does this, bypassing the menu) is unchanged.
## pending_seed carries the menu's explicit int seed for the next new
## campaign (-1 = none chosen yet; App derives one itself as a fallback).
var start_mode := "new"
var pending_seed := -1
