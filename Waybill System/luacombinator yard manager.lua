function numberOfSetBits(i)
  i = i - bit32.band(bit32.rshift(i,1), 0x55555555)
  i = bit32.band(i, 0x33333333) + bit32.band(bit32.rshift(i, 2), 0x33333333)
  return bit32.rshift( (bit32.band(i + bit32.rshift(i, 4), 0x0F0F0F0F) * 0x01010101), 24)
end

-- Items we have consumption dispatcher stops to program
consumerItems = {['iron-plate']=true}
-- Items we request from other yards
requestItems = {['iron-plate']=16, ['cargo-wagon']=16}

-- Yard ID constant
yard = 1

-- Collate yard contents
yardConnectors = {[1]=inputs[2].red, [33]=inputs[2].green, [65]=inputs[3].red, [97]=inputs[3].green}

-- Dictionary mapping item names to the dictionary of track numbers where those can be found
-- yardContents['iron-plate'][23]=true means iron-plate can be found on track 23
yardContents = {}

numEmpty = 0  -- how many tracks are empty this tick
numError = 0  -- how many tracks contain messed up wagons this tick

for offset, connector in pairs(yardConnectors) do
  for signal, value in pairs(connector) do
    if signal == 'signal-white' then
      numEmpty = numEmpty + numberOfSetBits(value)
    elseif signal == 'signal-black' then
      numError = numError + numberOfSetBits(value)
    else
      yardContents[signal] = yardContents[signal] or {}
      local i = value
      local track = offset
      while (i ~= 0) do           -- until all bits are zero
        if bit32.btest(i,1) then     -- check lower bit
          yardContents[signal][track] = true
        end
        track = track + 1
        i = bit32.rshift(i, 1)              -- shift bits, removing lower bit
      end -- while value>0
    end -- if signal
  end -- for signals
end -- for yardConnectors

local inventory = {}
for item,list in pairs(yardContents) do
  inventory[item] = table_size(list)
end
--outputs[2] = inventory


-- Update consumer assignments
-- Dictionary mapping item-names to the tracks that have been reserved for ongoing consumer deliveries
consumerDispatch = consumerDispatch or {}

-- Step 1: purge reservations after that track no longer contains the item in question
-- Step 2: check if any new trains have arrived at consumer dispatchers
-- Step 3: select tracks for consumer trains to visit and add them to the reservation list
waiting = inputs[1].green
consumerOutputs = consumerOutputs or {}
for item,_ in pairs(consumerItems) do
  -- Step 1: Copy list of reserved tracks, excluding ones that no longer contain the reserved item
  local validDispatch = {}
  if consumerDispatch[item] and next(consumerDispatch[item]) then
    for track, _ in pairs(consumerDispatch[item]) do
      if yardContents[item] and yardContents[item][track] then
        validDispatch[item] = validDispatch[item] or {}
        validDispatch[item][track] = true
      elseif consumerOutputs[item] and consumerOutputs[item] == track then
        -- This track no longer contains the correct item, cancel its dispatcher output and pick a new one
        consumerOutputs[item] = nil
      end
    end
  end
  consumerDispatch = validDispatch
  -- Step 2 & 3
  if (waiting[item] and waiting[item] > 0) then
    if (not consumerOutputs[item] or consumerOutputs[item] == 0) then
      if yardContents[item] then
        for track,_ in pairs(yardContents[item]) do
          -- make sure this track is not in the reservation list
          consumerDispatch[item] = consumerDispatch[item] or {}
          if not consumerDispatch[item][track] then
            consumerOutputs[item] = track
            consumerDispatch[item][track] = true
            break
          end
        end  -- for yardContents[item]
      end  -- if yardContents[item]
    end
  else
    -- no train waiting at dispatcher, clear output to that station
    consumerOutputs[item] = nil
  end -- if waiting[item]
end -- for consumerItems

-- output the consumer dispatcher instructions
outputs[1] = consumerOutputs

