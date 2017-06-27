/**
 * Created by marcus on 27.06.2017.
 */
kodi = require('kodi-ws')

kodi("localhost", 9090).catch(function (error) {
  console.log("ooops", error)
});