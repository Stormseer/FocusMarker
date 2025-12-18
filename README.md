
# Aryella's Focus Marker Assistant

This is a World of Warcraft addon that helps you with marking your focus target, inspired by the WeakAura "[Focus automarker](https://wago.io/9QzUcCuF_)" made by [RadioDesk#2770](https://wago.io/search/imports/wow/all?q=User%3A%22RadioDesk%232770%22). 

It maintains a macro (default: FocusMarker) in your global macro space, that looks something like this: <br>
```
    /focus [@mouseover,exists,nodead][]
    /tm [@mouseover,exists,nodead][] <1>
```
Where the "<1>" changes depending on your configuration (default raid marker: Star/Yellow).

The addon responds to the chat command "/focusmarker" or "/fm". On ready check the addon will also announce to your party (not while in a raid group) what your focus marker is currently set to, to help with potential marker conflicts.

Usage: 
| Command     | Description |
| ----------- | ----------- |
| /focusmarker      | Prints current marker and gives instructions on how to use slash commands.       |
| /focusmarker X   | Sets the marker of your choice, i.e "/focusmarker blue" will change your macro to use the square marker. Accepts both colors and shapes.         |
| /focusmarker options   | Opens the options panel.         |

If you attempt to change your marker during combat, the addon will wait until after combat to change it.

Full list of accepted aliases:
| Input       | Output |
| ----------- | ----------- |
| Yellow      | Star       |
| Y           | Star        |
| Star        | Star       |
| Orange      | Circle        |
| O           | Circle       |
| Circle      | Circle        |
| Purple      | Diamond       |
| P           | Diamond        |
| Diamond     | Diamond       |
| Bruno       | Diamond (an easter egg for a friend)       |
| Green       | Triangle       |
| G           | Triangle        |
| Triangle    | Triangle       |
| M           | Moon        |
| Moon        | Moon        |
| Blue        | Square        |
| B           | Square        |
| Square      | Square        |
| Red         | Cross        |
| R           | Cross        |
| X           | Cross        |
| Cross       | Cross        |
| White       | Skull        |
| W           | Skull        |
| Skull       | Skull        |
| None        | None        |
| Off         | None        |
| Default     | Star        |

Made by Aryella, on Silvermoon EU.

Curseforge: https://www.curseforge.com/wow/addons/focusmarker-assistant

