# #my-plugin configuration options
# Declare your config option for your plugin here. 
module.exports = {
  title: "Kodi plugin config options"
  type: "object"
  properties:
    debug:
      description: "Log information for debugging, including received messages"
      type: "boolean"
      default: false
    customOpenCommands:
      description: "Custom Player.Open commands"
      type: "array"
      default: []
      format: "table"
      items:
        type: "object"
        properties:
          name:
            type: "string"
          command:
            description: "The command"
            type: "string"

}
