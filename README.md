Pimatic-Kodi plugin
=======================

### Kodi Setup

To be able to use this plugin, the JSON-RPC remote control service via TCP (port 9090 by default) must be enabled. This 
 can be enabled by navigating to Settings / Services / Control and turning on the option "Allow remote control from 
 applications on other systems". Note, if pimatic is run on the kodi host and the option "Allow remote control from 
 applications on this system" is used instead, this may cause an error if the pimatic KodiPlayer device is setup 
 using the IPv4 loop-back address or "localhost". This is, as kodi only listens on the IPv6 loop-back address in 
 this mode. On Raspbian you can try to use hostname "ip6-localhost or use "Allow remote control from applications 
 on other systems" instead.

### Device Config Example

```json
{
  "id": "kodi-player",
  "name": "Kodi",
  "class": "KodiPlayer",
  "host": "192.168.1.2",
  "port": 9090
}
```

### Device Rules Examples

<b>Play music</b><br>
if smartphone is present then play Kodi

<b>Pause music</b><br>
if smartphone is absent then pause Kodi

<b>Next song</b><br>
if buttonNext is pressed then play next song on Kodi

<b>Previous song</b><br>
if buttonPrev is pressed then play previous song on Kodi

<b>Save yourself!</b><br>
if currentArtist of Kodi = "Justin Bieber" then play next song on Kodi


<b>Predictates examples</b>
if Kodi is playing then switch speakers on and dim lights to 30<br>
if Kodi is not playing then switch speakers off and dim lights to 100<br>

if Kodi is playing and kodi.type != "song" then dim lights to 30<br/>To make sure lights only dim if you are watching a movies/series.

### Custom Commands
You can add custom Player.Open commands to the plugin. Player.Open can execute almost anything.
From opening Youtube movies, Soundcloud streams to simple opening a file.

Example configuration for a custom command:
```json
{
  "plugin": "kodi",
  "customOpenCommands": [
    {
      "name": "nyan",
      "command": "plugin://plugin.video.youtube/?action=play_video&videoid=QH2-TGUlwu4"
    }
  ]
}
```

<b>Execute the custom command</b>
if yourrule then execute Open Command nyan on Kodi


This is just one of the examples you can do with the Player.Open command to Kodi,
This can also execute scripts in Kodi. 

You only need to find out what the script/plugin path is, and what parameter to give.

### Show Toasts
You can use GUI.ShowNotification to show toast messages on a Kodi player.

Example rules:
```
when: doorbell reports present
then: show Toast "Doorbell" on kodiplayer and pause kodiplayer

then: show Toast "Some Notification" with icon "error" on kodiplayer

then: show Toast "You have been informated" with icon "http://url.to/some_icon.png" on kodiplayer

then: show Toast "Short notice" with icon "info" for 1 second on kodiplayer

then: show Toast "Long notice" for 10 seconds on kodiplayer
```


### Note's
Big thanks to the code of Pimatic.
I used the [pimatic-mpd](https://github.com/pimatic/pimatic-mpd) plugin as a base for this project.



### TO DO
- Add volume controls
- create new device (template)
- better support for multimedia (now focused @ music)
