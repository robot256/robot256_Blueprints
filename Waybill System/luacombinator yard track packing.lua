-- inputs[2].red contains the yard-wide constant definitions
-- signal-Y = yard ID number
-- signal-C = yard column (group of 32 tracks)
-- signal-white = code for empty track (must be 0 or absent)
-- signal-black = code for error track (must be number of bits allocated for each track)
-- item-signals = code for each valid item (items not listed will be treated as errors)

-- inputs[1].red contains the per-track settings
-- dispatcher-station contains track # within this group of 32 tracks
if inputs[1].red and inputs[1].red['dispatcher-station'] and inputs[1].red['dispatcher-station'] > 0 then
  -- Make global track number
  localTrack = inputs[1].red['dispatcher-station']
  assert(localTrack <= 32, "Invalid track assignment.")
end
assert(localTrack and localTrack > 0, "Track not yet assigned with dispatcher-station signal.")

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
  column = contentsCodes['signal-C']
  
  -- Mask has as many bits as are allowed for each track.  Must be 2^N-1.
  local packedMask = contentsCodes['signal-black'] or 0x1F
  local bitsPerTrack = nil
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
  
  -- Find which N packed signals this column should output on.
  -- Each group of 32 tracks has exactly N signals to output N bits on.
  local packedOutputOrder = {}
  --local signalList = ""
  for i=1,bitsPerTrack do
    local packingIndex = (column-1)*bitsPerTrack + i
    assert(packingIndex <= #signalPackingOrder, "Not enough packed outputs signals defined.")
    packedOutputOrder[i] = signalPackingOrder[packingIndex]
  end
  
  -- Find which 1 or 2 packed signals this track should output on, with what shifts
  -- Dictionary of signalName -> bits to shift left (negative shifts right)
  local lsbIndex = (localTrack-1)*bitsPerTrack  -- starts at 0
  local msbIndex = lsbIndex + (bitsPerTrack-1)
  local startDwordIndex = math.floor(lsbIndex/32)  -- starts at 0
  local stopDwordIndex = math.floor(msbIndex/32)   -- starts at 0
  packedOutputSpec = {{name=packedOutputOrder[startDwordIndex+1], shift=(lsbIndex%32)}}
  if stopDwordIndex > startDwordIndex then
    -- MSBs are in the next word up
    table.insert(packedOutputSpec, {name=packedOutputOrder[stopDwordIndex+1], shift=((lsbIndex % 32) - 32)})
  end
end

track = localTrack + 32*(column-1)

-- Create output signal list of the given number at the correct offset in the packed signal sequence
function packOutput(code)
  local outsigs = {}
  for _,sig in pairs(packedOutputSpec) do
    local value = bit32.lshift(code, sig.shift)
    if value > (2^31-1) then
      value = value - 2^32
    end
    outsigs[sig.name] = value
  end
  return outsigs
end

-- Map LTN signals to wagon types.
-- If we decide to differentiate between different kinds of wagons, we'll need to change this table
if not valid_wagons then
  valid_wagons={['ltn-position-any-cargo-wagon']='cargo-wagon',
              ['ltn-position-any-fluid-wagon']='fluid-wagon'}
end

-- inputs[1].green contains inputs from LTN and Stringy train stops on this track
-- signal-red = train at stop
-- ltn-position-* = train wagon arrangement when dropping off
-- itmes = train contents
local trackInput = inputs[1].green

-- State machine generates outputs:
-- outputs[1] goes to LTN and Stringy stops on this track
-- signal-green = okay for train to leave
-- signal-pink = enable empty track dropoff stations
-- signal-cyan = enable full track pickup station
-- signal-red = track state is error, no stations enabled
--
-- outputs[2] goes to Yard Manager
-- Packed output signals indicating the code for the contents of this track at the proper bits.

-- Initialize the state machine
if not state then
  state = 0
  outputs[1] = {}
  outputs[2] = {}
  contents = nil
  wagons = nil
  err = false
end

if state == 0 then
  if trackInput['signal-red'] and trackInput['signal-red'] > 0 then
    -- Train just arrived. Act on its contents and send it away
    outputs[1] = {['signal-green'] = 1}
    outputs[2] = {}
    
    contents = nil
    wagons = nil
    err = false
    for signal,value in pairs(trackInput) do
      if value > 0 then
        if contentsCodes[signal] then
          if contents then
            err = true
            break
          else
            contents = signal
          end
        elseif valid_wagons[signal] then
          if wagons then
            err = true
            break
          else
            wagons = valid_wagons[signal]
          end
        elseif signal ~= "signal-red" and not string.find(signal,"ltn%-position") then
          err = true
          break
        end
      end
    end
    state = 1
  else
    -- Long delay waiting for train to arrive
    delay = 60
  end
elseif state == 1 then
  if not trackInput['signal-red'] or trackInput['signal-red'] == 0 then
    -- Train has left, we can change the stop names now
    if err then
      outputs[1] = string_to_signals('Y'..tostring(yard)..' ERROR')
      outputs[1]['signal-stopname']=1
      -- Don't enable any stations
      state = 2
    elseif contents then
      --rename stop to contents
      outputs[1] = string_to_signals('Y'..tostring(yard)..' PICKUP [item='..contents..'].'..tostring(track))
      outputs[1]['signal-stopname']=1
      outputs[1]['signal-stopname-richtext']=1
      -- Enable pickup stations
      state = 3
    elseif wagons then
      -- rename stop to wagons
      contents = wagons
      outputs[1] = string_to_signals('Y'..tostring(yard)..' PICKUP [item='..contents..'].'..tostring(track))
      outputs[1]['signal-stopname']=1
      outputs[1]['signal-stopname-richtext']=1
      -- Enable pickup stations
      state = 3
    else
      -- rename to empty
      outputs[1] = string_to_signals('Y'..tostring(yard)..' EMPTY.1')
      outputs[1]['signal-stopname']=1
      -- Enable dropoff stations
      state = 4
    end
  else
    -- Short delay waiting for train to leave
    delay = 10
  end
elseif state == 2 then
  -- Error state, all stops disabled
  outputs[1] = {['signal-red']=1}
  -- Send error signal to yard manager
  outputs[2] = packOutput(errorCode)
  state = 0
elseif state == 3 then
  -- Enable pickup stations
  outputs[1] = {['signal-cyan']=1,
                ['signal-couple']=1}
  -- Send inventory to the yard manager
  if contents and contentsCodes[contents] then
    outputs[2] = packOutput(contentsCodes[contents])
  else
    outputs[2] = packOutput(errorCode)
  end
  state = 0
elseif state == 4 then
  -- Enable dropoff stations
  outputs[1] = {['signal-pink']=1,
                ['signal-decouple']=2}
  outputs[2] = packOutput(emptyCode)
  state = 0
else
  state = 0
  outputs[1] = {}
  outputs[2] = {}
  contents = nil
  wagons = nil
  err = false
end
