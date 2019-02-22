# ##The plugin code

# Your plugin must export a single function, that takes one argument and returns a instance of
# your plugin class. The parameter is an envirement object containing all pimatic related functions
# and classes. See the [startup.coffee](http://sweetpi.de/pimatic/docs/startup.html) for details.
module.exports = (env) ->

  # ###require modules included in pimatic
  # To require modules that are included in pimatic use `env.require`. For available packages take
  # a look at the dependencies section in pimatics package.json

  EventEmitter = require('events').EventEmitter
  util = require 'util'
  Promise = env.require 'bluebird'
  assert = env.require 'cassert'
  M = env.matcher
  _ = env.require('lodash')
  milliseconds = require '../pimatic/lib/milliseconds'
  commons = require('pimatic-plugin-commons')(env)
  KodiApi = require 'kodi-ws'

  class KodiPlugin extends env.plugins.Plugin

    init: (app, @framework, @config) =>
      @debug = @config.debug ? false
      @base = commons.base @, 'KodiPlugin'
      @base.debug("Kodi plugin started")
      deviceConfigDef = require("./device-config-schema")

      @framework.deviceManager.registerDeviceClass("KodiPlayer", {
        configDef: deviceConfigDef.KodiPlayer,
        createCallback: (config) => new KodiPlayer(config)
      })

      @framework.ruleManager.addActionProvider(
        new KodiExecuteOpenActionProvider(@framework,@config)
      )
      @framework.ruleManager.addActionProvider(
        new KodiShowToastActionProvider(@framework,@config)
      )
      @framework.ruleManager.addPredicateProvider(new PlayingPredicateProvider(@framework))

    prepareConfig: (config) ->
      base = commons.base @, 'KodiPlugin'
      ['host', 'port'].forEach (key) ->
        if config[key]?
          base.info "Removing obsolete plugin configuration property: #{key}"
          delete config[key]

  class ConnectionProvider extends EventEmitter
    connection : null
    connected : false
    _host : ""
    _port : 0
    _emitter : null

    constructor: (host,port) ->
      @debug = kodiPlugin.config.debug ? false
      @base = commons.base @, "ConnectionProvider"
      @_host = host
      @_port = port

    getConnection: =>
      return new Promise((resolve, reject) =>
        if @connected
          resolve @connection
        else
          # make a new connection
          KodiApi(@_host, @_port).then((newConnection) =>
            @connected = true
            @connection = newConnection
            @emit 'newConnection'

            @connection.once "error", (() =>
              @connected = false
              @connection = null
            )
            @connection.once "close", (() =>
              @connected = false
              @connection = null
            )
            resolve @connection
          ).catch( (error) =>
            @base.debug 'connection rejected', error
            reject error
          )
      )

  class KodiPlayer extends env.devices.AVPlayer
    _type: ""
    _connectionProvider : null

    constructor: (@config) ->
      @name = @config.name
      @id = @config.id
      @debug = kodiPlugin.config.debug ? false
      @base = commons.base @, @config.class
      @interval = 60000

      @_state = 'stop'

      @actions = _.cloneDeep @actions
      @attributes =  _.cloneDeep @attributes

      @actions.executeOpenCommand =
        description: "Execute custom Player.Open command"

      @attributes.type =
        description: "The current type of the player"
        type: "string"

      @_connectionProvider = new ConnectionProvider(@config.host, @config.port)

      @_connectionProvider.on 'newConnection', =>
        @_connectionProvider.getConnection()
        .then (connection) =>
          connection.Player.OnPause (data) =>
            @base.debug 'Kodi Paused'
            @_setState 'pause'
            return

          connection.Player.OnStop =>
            @base.debug 'Kodi Stopped'
            @_setState 'stop'
            @_setCurrentTitle ''
            @_setCurrentArtist ''
            return

          connection.Player.OnPlay (data) =>
            @base.debug 'Kodi Playing'
            @_setState 'play'
            @_updatePlayer()
            .catch (error) =>
              @base.rejectWithErrorString null, error, "Unable to update player"
            return

        .catch (error) =>
          @base.error "Unable to register update handlers", error
        return

      @_updateInfo()
      super()

    destroy: () ->
      @base.cancelUpdate()
      super()

    getType: () -> Promise.resolve(@_type)

    play: () ->
      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.Player.GetActivePlayers().then (players) =>
          if players.length > 0
            connection.Player.PlayPause({"playerid":players[0].playerid, "play":true})
      .catch (error) =>
        @base.rejectWithErrorString Promise.reject, error, "Unable to play"

    pause: () ->
      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.Player.GetActivePlayers().then (players) =>
          if players.length > 0
            connection.Player.PlayPause({"playerid":players[0].playerid, "play":false})
      .catch (error) =>
        @base.rejectWithErrorString Promise.reject, error, "Unable to pause"


    stop: () ->
      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.Player.GetActivePlayers().then (players) =>
          if players.length > 0
            connection.Player.Stop({"playerid":players[0].playerid})
      .catch (error) =>
        @base.rejectWithErrorString Promise.reject, error, "Unable to stop"

    previous: () ->
      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.Player.GetActivePlayers().then (players) =>
          if players.length > 0
            connection.Player.GoTo({"playerid":players[0].playerid,"to":"previous"})
      .catch (error) =>
        @base.rejectWithErrorString Promise.reject, error, "Unable to select previous item"

    next: () ->
      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.Player.GetActivePlayers().then (players) =>
          if players.length > 0
            connection.Player.GoTo({"playerid":players[0].playerid,"to":"next"})
      .catch (error) =>
        @base.rejectWithErrorString Promise.reject, error, "Unable to select next item"

    setVolume: (volume) ->
      @base.info 'setVolume not implemented'

    executeOpenCommand: (command) =>
      @base.debug "Command", command

      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.Player.Open({
          item: { file : command}
          })
      .catch (error) =>
        @base.rejectWithErrorString Promise.reject, error, "Unable to execute open command"

    showToast: (message, icon, duration) =>
      opts = {title: 'Pimatic', 'message': message}

      if icon?
        opts['image'] = icon

      if duration?
        opts['displaytime'] = parseInt(duration, 10)

      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.GUI.ShowNotification(opts)
      .catch (error) =>
        @base.rejectWithErrorString Promise.reject, error, "Unable to send notification"

    _updateInfo: ->
      Promise.all([@_updatePlayerStatus(), @_updatePlayer()])
      .catch (error) =>
        @base.rejectWithErrorString null, error, "Unable to update player"
      .finally () =>
        @base.scheduleUpdate @_updateInfo, @interval

    _setType: (type) ->
      if @_type isnt type
        @_type = type
        @emit 'type', type

    _updatePlayerStatus: () ->
      @base.debug '_updatePlayerStatus'
      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.Player.GetActivePlayers()
        .then (players) =>
          if players.length > 0
            @base.debug "Found #{players.length} player(s)"
            connection.Player.GetProperties(
              {"playerid":players[0].playerid, "properties":["speed"]}
            ).then (data) =>
              @base.debug "Player.GetProperties", util.inspect data
              if data.speed? and data.speed > 0
                @base.debug 'Kodi Playing'
                @_setState 'play'
          else
            @base.debug 'Kodi Stopped'
            @_setState 'stop'
            @emit 'state', @_state
            return Promise.resolve()

    _updatePlayer: () ->
      @base.debug '_updatePlayer'
      @_connectionProvider.getConnection().then (connection) =>
        connection.Player.GetActivePlayers().then (players) =>
          if players.length > 0
            @base.debug "Found #{players.length} player(s)"
            connection.Player.GetItem(
              {"playerid":players[0].playerid, "properties":["title", "artist"]}
            ).then (data) =>
              @base.debug "Player.GetItem", util.inspect data
              info = data.item
              @_setType(info.type)
              @_setCurrentTitle(
                if info.title? and info.title isnt ''
                  info.title
                else if info.label?
                  info.label
                else ''
              )
              @_setCurrentArtist(if info.artist.length > 0 then info.artist[0] else "")
          else
            @_setCurrentArtist ''
            @_setCurrentTitle ''

    _sendCommandAction: (action) ->
      @base.debug '_sendCommandAction'
      @_connectionProvider.getConnection()
      .then (connection) =>
        connection.Input.ExecuteAction(action)
          .then (result) =>
            @base.debug "Result:", result
      .catch (error) =>
        @base.error "Unable to update player status", error
      return

  class KodiExecuteOpenActionProvider extends env.actions.ActionProvider
    constructor: (@framework,@config) ->
      @debug = kodiPlugin.config.debug ? false
      @base = commons.base @, "KodiExecuteOpenActionProvider"

    parseAction: (input, context) =>
      retVar = null

      kodiPlayers = _(@framework.deviceManager.devices).values().filter(
        (device) => device.hasAction("executeOpenCommand")
      ).value()
      if kodiPlayers.length is 0 then return

      device = null
      match = null
      state = null
      #get command names
      commandNames = []
      for command in @config.customOpenCommands
        commandNames.push(command.name)
      onDeviceMatch = ( (m , d) -> device = d; match = m.getFullMatch() )

      m = M(input, context)
        .match('execute Open Command ')
        .match(commandNames, (m,s) -> state = s.trim())
        .match(' on ')
        .matchDevice(kodiPlayers, onDeviceMatch)

      if match?
        assert device?
        assert (state) in commandNames
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new KodiExecuteOpenActionHandler(@framework, device, @config, state)
        }
      else
        return null

  class KodiExecuteOpenActionHandler extends env.actions.ActionHandler

    constructor: (@framework, @device, @config, @name) ->
      @debug = kodiPlugin.config.debug ? false
      @base = commons.base @, "KodiExecuteOpenActionHandler"

    executeAction: (simulate) =>
      if simulate
        for command in @config.customOpenCommands
          if command.name is @name
            return Promise.resolve __("would execute %s", command.command)
      else
        for command in @config.customOpenCommands
          @base.debug "checking for (1): #{command.name} == #{@name}"
          if command.name is @name
          
            {variables, functions} = @framework.variableManager.getVariablesAndFunctions()
            input = __('"%s"', command.command)
            context = M.createParseContext(variables, functions)
            match = null
            m = M(input, context)
            parseCommand = (m, tokens) => match = tokens 
            m.matchStringWithVars(parseCommand)
            
            return @framework.variableManager.evaluateStringExpression(match).then( (cmd) =>
              @device.executeOpenCommand(cmd).then( => 
                __("executed %s on %s", command.name, @device.name)
              )
            )

  class PlayingPredicateProvider extends env.predicates.PredicateProvider
    constructor: (@framework) ->
      @debug = kodiPlugin.config.debug ? false
      @base = commons.base @, "PlayingPredicateProvider"

    parsePredicate: (input, context) ->
      kodiDevices = _(@framework.deviceManager.devices).values()
        .filter((device) => device.hasAttribute( 'state')).value()

      device = null
      state = null
      negated = null
      match = null

      M(input, context)
        .matchDevice(kodiDevices, (next, d) =>
          next.match([' is', ' reports', ' signals'])
            .match([' playing', ' stopped',' paused', ' not playing'], (m, s) =>
              if device? and device.id isnt d.id
                context?.addError(""""#{input.trim()}" is ambiguous.""")
                return
              device = d
              mapping = {'playing': 'play', 'stopped': 'stop', 'paused': 'pause', 'not playing': 'not play'}
              state = mapping[s.trim()] # is one of  'playing', 'stopped', 'paused', 'not playing'

              match = m.getFullMatch()
            )
      )

      if match?
        assert device?
        assert state?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          predicateHandler: new PlayingPredicateHandler(device, state)
        }
      else
        return null

  class PlayingPredicateHandler extends env.predicates.PredicateHandler

    constructor: (@device, @state) ->
      @debug = kodiPlugin.config.debug ? false
      @base = commons.base @, "PlayingPredicateHandler"
      @dependOnDevice(@device)

    setup: ->
      @playingListener = (p) =>
        @base.debug "checking whether current state #{p} matches #{@state}"
        if @state is p or (@state is 'not play' and p isnt 'play')
          @emit 'change', true

      @device.on 'state', @playingListener
      super()

    getValue: ->
      return @device.getUpdatedAttributeValue('state').then(
        (p) =>
          @state is p or (@state is 'not play' and p isnt 'play')
      )

    destroy: ->
      @device.removeListener 'state', @playingListener
      super()

    getType: -> 'state'

  class KodiShowToastActionProvider extends env.actions.ActionProvider
    constructor: (@framework, @config) ->
      @debug = kodiPlugin.config.debug ? false
      @base = commons.base @, "KodiShowToastActionProvider"

    parseAction: (input, context) =>
      retVar = null

      kodiPlayers = _(@framework.deviceManager.devices)
        .filter( (device) => device instanceof KodiPlayer ).value()
      if kodiPlugin.length is 0 then return

      device = null
      match = null
      tokens = null
      iconTokens = []
      durationTokens = null
      durationUnit = null

      onDeviceMatch = ( (m, d) -> device = d; match = m.getFullMatch() )

      m = M(input, context)
        .match('show Toast ')
        .matchStringWithVars( (m, t) -> tokens = t )
        .optional( (m) =>
          m.match(' with icon ')
            .or([ ((m) => m.match(['"info"', '"warning"', '"error"'], (m, t) -> iconTokens = [t])),
              ((m) => m.matchStringWithVars( (m, t) -> iconTokens = t ))
            ])
        )
        .optional( (m) =>
          m.match(' for ')
            .matchTimeDurationExpression( (m, {tokens, unit}) =>
              durationTokens = tokens
              durationUnit = unit
            )
        )
        .match(' on ')
        .matchDevice(kodiPlayers, onDeviceMatch)

      if match?
        assert device?
        assert typeof match is "string"
        return {
          token: match
          nextInput: input.substring(match.length)
          actionHandler: new KodiShowToastActionHandler(@framework, device, @config, tokens, iconTokens, durationTokens, durationUnit)
        }
      else
        return null

  class KodiShowToastActionHandler extends env.actions.ActionHandler
    constructor: (@framework,@device,@config,@messageTokens,@iconTokens,@durationTokens,@durationUnit) ->
      @debug = kodiPlugin.config.debug ? false
      @base = commons.base @, "KodiShowToastActionHandler"

    executeAction: (simulate) =>
      toastPromise = (message, icon, duration) =>
        if simulate
          return Promise.resolve __("would show toast %s with icon %s for %s", message, icon, duration)
        else
          @base.debug "Sending toast %s with icon %s for %s on %s" % message, icon, duration, @device
          return @device.showToast(message, icon, duration).then( => __("show toast %s with icon %s for %s on %s", message, icon, duration, @device.name))

      timeLookup = Promise.resolve(null)
      if @durationTokens? and @durationUnit?
        timeLookup = Promise.resolve(@framework.variableManager.evaluateStringExpression(@durationTokens).then( (time) =>
          return milliseconds.parse "#{time} #{@durationUnit}"
        ))

      timeLookup.then( (time) =>
        @framework.variableManager.evaluateStringExpression(@messageTokens).then( (message) =>
          if @iconTokens is null or @iconTokens.length == 0
            return toastPromise(message, null, time)
          else
            @framework.variableManager.evaluateStringExpression(@iconTokens).then( (icon) =>
              return toastPromise(message, icon, time)
            )
        )
      )

  kodiPlugin = new KodiPlugin
  return kodiPlugin
