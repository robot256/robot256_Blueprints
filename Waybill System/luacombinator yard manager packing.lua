-- inputs[2].red contains the yard-wide constant definitions
-- signal-Y = yard ID number
-- signal-C = yard column (group of 32 tracks)
-- signal-white = code for empty track (must be 0 or absent)
-- signal-black = code for error track (must be number of bits allocated for each track)
-- item-signals = code for each valid item (items not listed will be treated as errors)


if inputs[2].red and inputs[2].red['signal-Y'] and inputs[2].red['signal-Y'] > 0 then
  -- Global inputs active, change stored global variables

  local signalPackingOrder = {'signal-0','signal-1','signal-2','signal-3','signal-4','signal-5',
      'signal-6','signal-7','signal-8','signal-9','signal-A','signal-B','signal-C','signal-D',
      'signal-E','signal-F','signal-G','signal-H','signal-I','signal-J','signal-K','signal-L',
      'signal-M','signal-N','signal-O','signal-P','signal-Q','signal-R','signal-S','signal-T',
      'signal-U','signal-V','signal-W','signal-X','signal-Y','signal-Z',
      'signal-red','signal-yellow','signal-green','signal-cyan'}

  contentsCodes = inputs[2].red
  yard = contentsCodes['signal-Y']
  columns = contentsCodes['signal-C']
  
  -- Mask has as many bits as are allowed for each track.  Must be 2^N-1.
  local packedMask = contentsCodes['signal-black']
  bitsPerTrack = nil
  if packedMask==0x3 then bitsPerTrack = 2
  elseif packedMask==0x7 then bitsPerTrack = 3
  elseif packedMask==0xF then bitsPerTrack = 4
  elseif packedMask==0x1F then bitsPerTrack = 5
  elseif packedMask==0x3F then bitsPerTrack = 6
  elseif packedMask==0x7F then bitsPerTrack = 7
  elseif packedMask==0xFF then bitsPerTrack = 8 end
  assert(bitsPerTrack ~= nil, "Invalid mask set on signal-black")

  -- Clear virtual signals from code lookup dictionary
  contentsCodes['signal-Y'] = nil
  contentsCodes['signal-C'] = nil
  contentsCodes['signal-white'] = nil
  contentsCodes['signal-black'] = nil
  emptyCode = 0
  errorCode = packedMask
  
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

-- Dictionary mapping item-names to the tracks that have been reserved for ongoing consumer deliveries
consumerDispatch = consumerDispatch or {}

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
  if consumerDispatch[item] then
    inventory[item] = inventory[item] - table_size(consumerDispatch[item])
  end
end
inventory['signal-white'] = numEmpty
outputs[2] = inventory


-- Update consumer assignments

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

