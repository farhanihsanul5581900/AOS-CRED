-- My AOS PID : Fw8GRIa8aMxU_FyPEs2fsfjF7OYa0_7OHJ7KEATJhTM

-- Adaptive Learning from Opponents
-- Dynamic Energy Management:

-- Initializing global variables to store the latest game state and game host process.
LatestGameState = {}  -- Stores all game data
InAction = false     -- Prevents your bot from doing multiple actions
OpponentPatterns = {} -- Stores opponent patterns

colors = {
  red = "\27[31m",
  green = "\27[32m",
  blue = "\27[34m",
  reset = "\27[0m",
  gray = "\27[90m"
}

-- Checks if two points are within a given range.
-- @param x1, y1: Coordinates of the first point.
-- @param x2, y2: Coordinates of the second point.
-- @param range: The maximum allowed distance between the points.
-- @return: Boolean indicating if the points are within the specified range.
function inRange(x1, y1, x2, y2, range)
    return math.abs(x1 - x2) <= range and math.abs(y1 - y2) <= range
end

-- Decide the next action based on player proximity, energy, health, and game map analysis.
function decideNextAction()
  local player = LatestGameState.Players[ao.id]
  local targetInRange = false
  local bestTarget = nil

  -- Find closest and weakest target within attack range
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id and inRange(player.x, player.y, state.x, state.y, 1) then
      targetInRange = true
      if not bestTarget or state.health < bestTarget.health or (state.health == bestTarget.health and inRange(player.x, player.y, state.x, state.y, 1) < inRange(player.x, player.y, bestTarget.x, bestTarget.y, 1)) then
        bestTarget = state
      end
    end
  end

  if player.energy > 5 and targetInRange then
    print(colors.red .. "Player in range. Attacking." .. colors.reset)
    ao.send({
      Target = Game,
      Action = "PlayerAttack",
      Player = ao.id,
      AttackEnergy = tostring(player.energy),
    })
  else
    print(colors.red .. "No player in range or low energy. Moving randomly." .. colors.reset)
    local directionRandom = {"Up", "Down", "Left", "Right"}
    local randomIndex = math.random(#directionRandom)
    ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = directionRandom[randomIndex]})
  end
  InAction = false
end

-- Adaptive learning from opponents
function learnFromOpponents()
  local player = LatestGameState.Players[ao.id]
  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id then
      -- Record opponent's actions
      if not OpponentPatterns[target] then
        OpponentPatterns[target] = {}
      end
      table.insert(OpponentPatterns[target], {x = state.x, y = state.y, action = state.lastAction})
      
      -- Analyze opponent's patterns
      local pattern = OpponentPatterns[target]
      if #pattern > 5 then
        local recentActions = {}
        for i = #pattern - 4, #pattern do
          table.insert(recentActions, pattern[i].action)
        end
        if table.concat(recentActions) == "MoveMoveMoveMoveMove" then
          -- Predict opponent will move again
          local direction = calculateDirection(player.x, player.y, state.x, state.y)
          ao.send({Target = Game, Action = "PlayerMove", Player = ao.id, Direction = direction})
          InAction = false
          return true
        end
      end
    end
  end
  return false
end

-- Dynamic energy management
function dynamicEnergyManagement()
  local player = LatestGameState.Players[ao.id]
  local bestTarget = nil

  for target, state in pairs(LatestGameState.Players) do
    if target ~= ao.id then
      if not bestTarget or state.health < bestTarget.health or (state.health == bestTarget.health and player.energy > state.energy) then
        bestTarget = state
      end
    end
  end

  if bestTarget then
    local energyToUse = math.min(player.energy, bestTarget.health)
    print(colors.green .. "Adjusting energy for optimal attack." .. colors.reset)
    ao.send({
      Target = Game,
      Action = "PlayerAttack",
      Player = ao.id,
      AttackEnergy = tostring(energyToUse),
    })
    InAction = false
    return true
  end
  return false
end

-- Calculate direction to move towards target position
function calculateDirection(x1, y1, x2, y2)
  if x1 < x2 then
    return "Right"
  elseif x1 > x2 then
    return "Left"
  elseif y1 < y2 then
    return "Down"
  else
    return "Up"
  end
end

-- Handler to print game announcements and trigger game state updates.
Handlers.add(
  "PrintAnnouncements",
  Handlers.utils.hasMatchingTag("Action", "Announcement"),
  function (msg)
    if msg.Event == "Started-Waiting-Period" then
      ao.send({Target = ao.id, Action = "AutoPay"})
    elseif (msg.Event == "Tick" or msg.Event == "Started-Game") and not InAction then
      InAction = true
      ao.send({Target = Game, Action = "GetGameState"})
    elseif InAction then
      print("Previous action still in progress. Skipping.")
    end
    print(colors.green .. msg.Event .. ": " .. msg.Data .. colors.reset)
  end
)

-- Handler to trigger game state updates.
Handlers.add(
  "GetGameStateOnTick",
  Handlers.utils.hasMatchingTag("Action", "Tick"),
  function ()
    if not InAction then
      InAction = true
      print(colors.gray .. "Getting game state..." .. colors.reset)
      ao.send({Target = Game, Action = "GetGameState"})
    else
      print("Previous action still in progress. Skipping.")
    end
  end
)

-- Handler to automate payment confirmation when waiting period starts.
Handlers.add(
  "AutoPay",
  Handlers.utils.hasMatchingTag("Action", "AutoPay"),
  function (msg)
    print("Auto-paying confirmation fees.")
    ao.send({ Target = Game, Action = "Transfer", Recipient = Game, Quantity = "1000"})
  end
)

-- Handler to update the game state upon receiving game state information.
Handlers.add(
  "UpdateGameState",
  Handlers.utils.hasMatchingTag("Action", "GameState"),
  function (msg)
    local json = require("json")
    LatestGameState = json.decode(msg.Data)
    ao.send({Target = ao.id, Action = "UpdatedGameState"})
    print("Game state updated. Print 'LatestGameState' for detailed view.")
  end
)

-- Handler to decide the next best action.
Handlers.add(
  "decideNextAction",
  Handlers.utils.hasMatchingTag("Action", "UpdatedGameState"),
  function ()
    if LatestGameState.GameMode ~= "Playing" then
      InAction = false
      return
    end
    print("Deciding next action.")

    -- Check for learning from opponents
    if learnFromOpponents() then
      return
    end

    -- Check for dynamic energy management
    if dynamicEnergyManagement() then
      return
    end

    -- Default action
    decideNextAction()
    ao.send({Target = ao.id, Action = "Tick"})
  end
)

-- Handler to automatically attack when hit by another player.
Handlers.add(
  "ReturnAttack",
  Handlers.utils.hasMatchingTag("Action", "Hit"),
  function (msg)
    if not InAction then
      InAction = true
      local playerEnergy = LatestGameState.Players[ao.id].energy
      if playerEnergy == nil then
        print(colors.red .. "Unable to read energy." .. colors.reset)
        ao.send({Target = Game, Action = "Attack-Failed", Reason = "Unable to read energy."})
      elseif playerEnergy == 0 then
        print(colors.red .. "Player has insufficient energy." .. colors.reset)
        ao.send
