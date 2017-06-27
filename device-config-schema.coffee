module.exports ={
  title: "pimatic-Kodi device config schemas"
  KodiPlayer: {
    title: "KodiPlayer config options"
    type: "object"
    extensions: ["xLink"]
    properties:
      port:
        description: "The port for Kodi RPC (Default: 9090)"
        type: "integer"
        default: 9090
      host:
        description: "The address of the Kodi host"
        type: "string"
        default: "localhost"
  }
}