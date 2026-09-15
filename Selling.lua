-- Chain: your side of the counter.
--
-- Every other file here is written for the man paying. This one is for the
-- man being paid. It is the same argument seen from the other chair - "that
-- was five", "that was three" - and it ends the same way: with a count that
-- both of you watched go up, in party chat, run by run.
--
-- What it does not do is advertise for you. A line goes out when you press
-- the button and never otherwise: no timer, no repeat, nothing that carries
-- on while you are tabbed out. That is not caution about the rules so much as
-- about the channel - an addon that posts on its own is what gets everybody
-- else's addon banned from the channel.

local ADDON, BT = ...
local C = BT.COL

local function Short(name)
  if not name then return nil end
  return (BT.ShortName and BT.ShortName(name)) or name
end

--------------------------------------------------------------------------
-- Whether you are selling at all
--------------------------------------------------------------------------
-- Everything on this side used to be always on: anybody in your group who
-- handed you gold became a customer, and the count went out in party chat
-- whether or not you were running anything for anybody. A guild mate paying
-- back a loan at the summoning stone is not a customer.
--
-- So there is a switch, and it is off until you say otherwise. It is per
-- character, because selling is something one of your characters does on a
-- given evening, and it is the button you press when you sit down to work.
function BT.Selling()
  return ChainCharDB.selling and true or false
end

function BT.SetSelling(on)
  if on == nil then on = not BT.Selling() end
  ChainCharDB.selling = on and true or nil
  if on then ChainCharDB.sellingAt = time() else ChainCharDB.sellingAt = nil end
  if BT.RenderWindow then BT.RenderWindow() end
  if BT.Refresh then BT.Refresh() end
  return BT.Selling()
end

--------------------------------------------------------------------------
-- What you charge
--------------------------------------------------------------------------
local function Sell()
  ChainDB.sell = ChainDB.sell or {}
  local s = ChainDB.sell
  s.price = s.price or {}
  s.ads = s.ads or {}
  if s.announce == nil then s.announce = true end
  return s
end
BT.Sell = Sell

-- Gold for a pack, and how many runs that pack is. Per instance, because
-- Maraudon and the Stockades are not the same job; the last thing you typed
-- stands in for an instance you have not priced yet.
function BT.SellPrice(id)
  local s = Sell()
  local p = id and s.price[id] or nil
  local gold = (p and p.gold) or s.gold or 0
  local pack = (p and p.pack) or s.pack or ChainDB.pack or 5
  return gold, math.max(1, pack)
end

function BT.SetSellPrice(id, gold, pack)
  local s = Sell()
  gold = math.max(0, tonumber(gold) or 0)
  pack = math.max(1, math.floor(tonumber(pack) or 0))
  if id then s.price[id] = { gold = gold, pack = pack } end
  -- and remembered as the general figure, so the next instance starts from
  -- what you charge rather than from zero
  s.gold, s.pack = gold, pack
  return gold, pack
end

-- Copper one run costs at your price. Zero when you have not set one, which
-- every caller has to handle: guessing a price is how a customer ends up
-- owed runs he never bought.
function BT.SellPerRun(id)
  local gold, pack = BT.SellPrice(id)
  if gold <= 0 then return 0 end
  return (gold * 10000) / pack
end

--------------------------------------------------------------------------
-- Who has paid you
--------------------------------------------------------------------------
-- Per character: the boost you are running is this character's, and a list
-- that followed you to your bank alt would be a list of strangers.
function BT.Customers()
  ChainCharDB.customers = ChainCharDB.customers or {}
  return ChainCharDB.customers
end

function BT.Customer(name)
  name = Short(name)
  if not name then return nil end
  for _, c in ipairs(BT.Customers()) do
    if c.name == name then return c end
  end
  return nil
end

local function Make(name)
  local c = BT.Customer(name)
  if c then return c end
  c = { name = Short(name), paid = 0, runs = 0, done = 0, at = time() }
  table.insert(BT.Customers(), c)
  return c
end

-- Everybody in the group right now, by short name. A run counts for the
-- people who were actually in it: somebody who paid and then left owes you
-- nothing and is owed nothing until he comes back.
function BT.GroupNames()
  local out = {}
  local me = UnitName and UnitName("player")
  if me then out[Short(me)] = true end
  if not (IsInGroup and IsInGroup() and UnitExists) then return out end
  local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
  local size = (prefix == "raid") and 40 or 4
  for i = 1, size do
    local u = prefix .. i
    if UnitExists(u) then
      local n = UnitName and UnitName(u)
      if n then out[Short(n)] = true end
    end
  end
  return out
end

-- Money came in. Turned into runs at your price, now, and kept as gold as
-- well: the price can change afterwards and what he handed you cannot.
function BT.CustomerPaid(name, copper, id)
  copper = tonumber(copper) or 0
  if copper <= 0 then return nil end
  -- not while you are not selling: money from somebody in your group is a
  -- loan being repaid as often as it is a boost being bought
  if not BT.Selling() then return nil end
  local per = BT.SellPerRun(id)
  if per <= 0 then
    -- No price set, so we cannot say what it bought. He still goes on the
    -- list with his gold on it - a name and a number you can finish yourself
    -- beats a payment that vanished.
    local c = Make(name)
    c.paid = (c.paid or 0) + copper
    c.at = time()
    if BT.RenderWindow then BT.RenderWindow() end
    return c
  end
  local c = Make(name)
  c.paid = (c.paid or 0) + copper
  c.runs = (c.runs or 0) + copper / per
  c.per = per
  c.id = id or c.id
  c.at = time()
  if BT.RenderWindow then BT.RenderWindow() end
  if Sell().announce then
    local left = math.max(0, (c.runs or 0) - (c.done or 0))
    BT.SayToGroup(c.name .. " " .. BT.SellCount(c) .. " - "
      .. BT.G(BT.Gold(copper)) .. " in, " .. BT.Runsish(left) .. " to go")
  end
  return c
end

-- "2/5", or "2" when nobody has said how many he bought
function BT.SellCount(c)
  local done = math.floor((c.done or 0) + 0.5)
  local of = (c.runs or 0)
  if of <= 0 then return tostring(done) end
  return done .. "/" .. math.floor(of + 0.5)
end

function BT.Runsish(n)
  n = n or 0
  local s = string.format((math.abs(n - math.floor(n + 0.5)) < 0.05)
    and "%.0f" or "%.1f", n)
  return s .. " run" .. ((s == "1") and "" or "s")
end

function BT.SetCustomerRuns(name, left)
  local c = BT.Customer(name)
  if not c then return nil end
  left = tonumber(left)
  if not left then return nil end
  -- you are typing what he has left, so what he bought is that plus what he
  -- has had. Editing the total would silently undo the runs already done.
  c.runs = math.max(0, (c.done or 0) + math.max(0, left))
  if BT.RenderWindow then BT.RenderWindow() end
  return c.runs
end

function BT.RemoveCustomer(name)
  name = Short(name)
  local list = BT.Customers()
  for i = #list, 1, -1 do
    if list[i].name == name then table.remove(list, i) end
  end
  if BT.RenderWindow then BT.RenderWindow() end
end

function BT.ClearCustomers()
  ChainCharDB.customers = {}
  if BT.RenderWindow then BT.RenderWindow() end
end

--------------------------------------------------------------------------
-- Counting the runs out loud
--------------------------------------------------------------------------
-- One line, not one per customer. After every run, with four names on the
-- list, a line each is twenty lines an hour in somebody else's chat window -
-- and the thing they want to read is one number each anyway.
function BT.SellLine()
  local here = BT.GroupNames()
  local bits, done = {}, {}
  for _, c in ipairs(BT.Customers()) do
    if here[c.name] then
      local left = (c.runs or 0) - (c.done or 0)
      bits[#bits + 1] = c.name .. " " .. BT.SellCount(c)
      if (c.runs or 0) > 0 and left <= 0.05 then done[#done + 1] = c.name end
    end
  end
  if #bits == 0 then return nil end
  local line = table.concat(bits, "   ")
  if #done > 0 then
    line = line .. "  -  " .. table.concat(done, ", ")
      .. ((#done == 1) and " is done" or " are done")
  end
  return line
end

-- Say it now, whether or not a run just ended: the button under the list.
function BT.SaySellCount()
  local line = BT.SellLine()
  if not line then return false end
  return BT.SayToGroup(line) and true or false
end

-- A run finished and you were the one clearing it. Everybody on the list who
-- is still in the group has had one.
function BT.SellRunDone()
  if not BT.Selling() then return nil end
  local list = BT.Customers()
  if #list == 0 then return nil end
  local here = BT.GroupNames()
  local any, spent = false, false
  for _, c in ipairs(list) do
    if here[c.name] then
      local of = c.runs or 0
      -- A pack stops at its own size. Two customers in one group rarely buy
      -- the same number - one takes five and somebody joins two runs later
      -- and takes ten - so the short one runs out first, and he is usually
      -- still standing there while the long one carries on. His count used to
      -- go 6/5, 7/5, which is the addon saying he has had more than he paid
      -- for in front of the man he paid.
      --
      -- Somebody who paid with no price set has no total to stop at, so he
      -- keeps counting: what we have is how many he has had.
      if of > 0 and (c.done or 0) + 0.05 >= of then
        spent = true
      else
        c.done = (c.done or 0) + 1
        any = true
      end
    end
  end
  if not any then
    -- everybody present is out of runs: they were told so on the run that
    -- finished them, and saying it again every run is nagging
    if spent and BT.RenderWindow then BT.RenderWindow() end
    return nil
  end
  if BT.RenderWindow then BT.RenderWindow() end
  if Sell().announce then BT.SaySellCount() end
  return true
end

--------------------------------------------------------------------------
-- The advert
--------------------------------------------------------------------------
-- What you would type yourself, kept per instance so the one for Maraudon is
-- not the one for the Stockades with the name changed by hand each time.
function BT.SellAd(id)
  local s = Sell()
  local text = id and s.ads[id] or nil
  if text and text ~= "" then return text end
  return nil
end

function BT.SetSellAd(id, text)
  local s = Sell()
  if not id then return nil end
  text = tostring(text or "")
  s.ads[id] = (text ~= "") and text or nil
  return s.ads[id]
end

-- The line to start from, when you have not written one. Built out of what
-- you charge, so it is right rather than a placeholder.
function BT.SellAdDefault(step)
  local id = step and step.id
  local gold, pack = BT.SellPrice(id)
  local where = (step and (step.label or step.zone)) or "boost"
  if gold <= 0 then
    return "WTS " .. where .. " boost - pst"
  end
  return "WTS " .. where .. " boost - " .. BT.G(gold) .. " for " .. pack
    .. " runs - pst"
end

-- One press, one line. The wait is on us rather than on the server: the
-- channel throttle answers a flood by muting you for ten minutes, and a
-- button that can be leaned on is a button that will be.
local AD_WAIT = 30
local lastAd = 0

function BT.AdWait()
  local left = AD_WAIT - ((GetTime and GetTime() or 0) - lastAd)
  return (left > 0) and math.ceil(left) or 0
end

function BT.PostAd(text)
  text = tostring(text or "")
  if text == "" then return false, "nothing to post" end
  if BT.AdWait() > 0 then
    return false, "wait " .. BT.AdWait() .. "s - the channel throttles"
  end
  if type(GetChannelName) ~= "function" or type(SendChatMessage) ~= "function" then
    return false, "cannot reach the channel"
  end
  local n = GetChannelName("LookingForGroup")
  if not n or n == 0 then
    return false, "you are not in LookingForGroup - /join LookingForGroup"
  end
  SendChatMessage(text, "CHANNEL", nil, n)
  lastAd = GetTime and GetTime() or 0
  return true
end
