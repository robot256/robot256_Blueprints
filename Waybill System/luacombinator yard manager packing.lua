-- inputs[2].red contains the yard-wide constant definitions
-- signal-Y = yard ID number
-- signal-C = Total number of yard colunms (groups of 32 tracks)
-- signal-white = code for vacant track (must be 0 or absent)
-- signal-black = code for error track (must be number of bits allocated for each track)
-- item-signals[bits 7:0] = code for each valid item, range 1:errorCode-1 (items not listed will be treated as errors)
-- item-signals[bits 15:8] = Logistics request threshold (request more when we have fewer than this)
-- item-signals[bits 23:16] = Logistics preferred value (will request up to this amount, and provide down to this amount)
-- item-signals[bits 31:24] = Logistics provide threshold (provide excess when we have more than this)
--
-- If item-signals[bits 7:0] is zero but upper bits are set, upper bits will be ignored.
-- Example: iron-plate = 1<<0 + 4<<8 + 19<<16 + 255<<24
--   iron-plate is encoded as "1"
--   iron-plate is requested when there are 3 or fewer left in the yard
--   when iron-plate is requested, enough is requested so that we will have 19 in the yard
--   iron-plate is provided ony if there are 256 of it in the yard (will never happen)
--
-- Example: advanced-circuit = 5<<0 + 0<<8 + 0<<16 + 8<<24
--   advanced-circuit is encoded as "5"
--   advanced-circuit is never requested
--   when advanced-circuit is provided, all available units are fair game
--   advanced-circuit is provided only once there are 8 units stored in the yard
--
-- Example: cargo-wagon = 14<<0 + 5<<8 + 16<<16 + 31<<24
--   cargo-wagon (empty cargo wagon unit) is encoded as "14"
--   empty cargo wagons are requested if there are 4 or fewer in the yard
--   when empty cargo wagons are requested, yard is filled to 16 units
--   if there are ever 32 or more emptys here, they can be provided to other yards
--
-- inputs[2].green contains the yard contents
--   


constConnector = inputs[2].red

signalPackingOrder = {'signal-0','signal-1','signal-2','signal-3','signal-4','signal-5',
      'signal-6','signal-7','signal-8','signal-9','signal-A','signal-B','signal-C','signal-D',
      'signal-E','signal-F','signal-G','signal-H','signal-I','signal-J','signal-K','signal-L',
      'signal-M','signal-N','signal-O','signal-P','signal-Q','signal-R','signal-S','signal-T',
      'signal-U','signal-V','signal-W','signal-X','signal-Y','signal-Z',
      'signal-red','signal-yellow','signal-green','signal-cyan'}

if constConnector and constConnector['signal-Y'] and constConnector['signal-Y'] > 0 then
  -- Global inputs active, change stored global variables

  contentsCodes = constConnector
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
  vacantCode = 0
  errorCode = packedMask
  
  -- Mask the remaining signal codes to the lower 8 bits
  -- Extract the logistics parameters too
  requestThreshold = {}
  requestAmount = {}
  provideThreshold = {}
  codeLookup = {}
  consumerItems = {}
  for sig,val in pairs(contentsCodes) do
    requestThreshold[sig] = bit32.band(bit32.rshift(val,8), 0xFF)
    requestAmount[sig] = bit32.band(bit32.rshift(val,16), 0xFF)
    provideThreshold[sig] = bit32.band(bit32.rshift(val,24), 0xFF)
    contentsCodes[sig] = bit32.band(val, 0xFF)
    codeLookup[bit32.band(val, 0xFF)] = sig
    if requestAmount[sig] > 0 then
      consumerItems[sig] = true
    end
  end
  
  -- Generate yard data unpacking table for one column
  packedOutputSpecList = {}
  for ct=1,32 do
    local lsbIndex = (ct-1)*bitsPerTrack  -- starts at 0
    local startDwordIndex = math.floor(lsbIndex/32)  -- starts at 0
    local stopDwordIndex = math.floor((lsbIndex + (bitsPerTrack-1))/32)   -- starts at 0
    local shifty = (lsbIndex%32)
    local masky = bit32.lshift(packedMask,(lsbIndex%32))
    if masky >= 2^31 then masky = masky - 2^32 end
    local spec = {{index=startDwordIndex+1, shift=shifty, mask=masky}}
    if stopDwordIndex > startDwordIndex then
      -- MSBs are in the next word up
      shifty = ((lsbIndex % 32) - 32)
      masky = bit32.lshift(packedMask,(lsbIndex%32)-32)
      if masky >= 2^31 then masky = masky - 2^32 end
      table.insert(spec, {index=stopDwordIndex+1, shift=shifty, mask=masky})
      --assert(ct~=7,"ct="..tostring(ct)..", index="..tostring(stopDwordIndex+1)..", shift="..tostring(shifty)..", mask="..tostring(masky))
    end
    table.insert(packedOutputSpecList, spec)
    
  end
  
end


yardConnector = inputs[2].green

-- Dictionary mapping item names to the dictionary of track numbers where those can be found
-- yardContents['iron-plate'][23]=true means iron-plate can be found on track 23
yardContents = {}

-- Dictionary mapping item-names to the tracks that have been reserved for ongoing consumer deliveries
consumerDispatch = consumerDispatch or {}

numVacant = 0  -- how many tracks are vacant this tick
numError = 0  -- how many tracks contain messed up wagons this tick
numUnknown = 0
outputs[2] = {}
for col=1,columns do
  local colSigs = {signalPackingOrder[(col-1)*5+1], signalPackingOrder[(col-1)*5+2], signalPackingOrder[(col-1)*5+3],
             signalPackingOrder[(col-1)*5+4], signalPackingOrder[(col-1)*5+5]}
  -- repeat for all 32 tracks in this column
  for colt=1,32 do
    -- Check the bits for this track
    local spec = packedOutputSpecList[colt]
    local code = 0
    for _,word in pairs(spec) do
      if yardConnector[colSigs[word.index]] then
        --assert(false,"colt="..tostring(colt)..", signal present="..colSigs[word.index])
        code = code + bit32.rshift(bit32.band(yardConnector[colSigs[word.index]],word.mask),word.shift)
      end
    end
    --assert(colt~=3,"Code #"..tostring(colt).." = "..tostring(code))
    if code == vacantCode then
      numVacant = numVacant + 1
    elseif codeLookup[code] then
      local track = (col-1)*32 + colt
      yardContents[codeLookup[code]] = yardContents[codeLookup[code]] or {}
      yardContents[codeLookup[code]][track] = true
      --assert(false,"Added "..codeLookup[code].." to track "..tostring(track))
    elseif code == errorCode then
      numError = numError + 1
    else
      numUnknown = numUnknown + 1
      --assert(false,"Code #"..tostring(colt).." = "..tostring(code))
    end
  end
end

--assert(false,serpent.block(yardContents))


local inventory = {}
for item,list in pairs(yardContents) do
  inventory[item] = table_size(list)
  if consumerDispatch[item] then
    inventory[item] = inventory[item] - table_size(consumerDispatch[item])
  end
end
inventory['signal-white'] = numVacant
inventory['signal-red'] = numError
inventory['signal-yellow'] = numUnknown
outputs[2] = inventory


-- Update consumer assignments

-- Step 1: purge reservations after that track no longer contains the item in question
-- Step 2: check if any new trains have arrived at consumer dispatchers
-- Step 3: select tracks for consumer trains to visit and add them to the reservation list

-- inputs[1].green: Inputs from Waiting stops on common green bus.
--    Waiting stops are Dispatcher stops named "Y<X> PICKUP [item=<ITEM>]"
--    Configured to output stopped train on <ITEM>
--
-- outputs[1] (red wire): Each Waiting Dispatcher stop has a buffer combinator translating that <ITEM> to signal-dispatcher on the red wire.


waiting = inputs[1].green
consumerOutputs = consumerOutputs or {}
local validDispatch = {}
  for item,_ in pairs(contentsCodes) do
  -- Step 1: Copy list of reserved tracks, excluding ones that no longer contain the reserved item
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
end
consumerDispatch = validDispatch


-- Step 2 & 3
for item,_ in pairs(contentsCodes) do
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
    consumerOutputs[item] = 0
  end -- if waiting[item]
end -- for consumerItems

-- output the consumer dispatcher instructions
outputs[1] = consumerOutputs

