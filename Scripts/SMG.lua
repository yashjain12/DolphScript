local core = require "SMG_core"
local vec = require "Vector_Math"
local tilt = require "tilt_bonus"

local ILStartFrame = 132818
function getILTime()
	local currentTime = GetFrameCount()
	local frames = currentTime - ILStartFrame
	return string.format("%.2f", (GetFrameCount() - 1897) / 60)
end


local lastSpd = 0
function getEfficiency()
	local eff = 0
	if lastSpd ~= 0 then
		eff = core.Spd().XYZ / lastSpd * 100
	end
	lastSpd = math.sqrt(core.BaseVelocity().X^2 + core.BaseVelocity().Y^2 + core.BaseVelocity().Z^2)
	return eff
end


local yaw = 0
function getAngle(v, goal_angle) -- input speed or velocity
	local g = {core.DownGravity().X, core.DownGravity().Y, core.DownGravity().Z}
	local pitch = vec.angle(g, {0, -1, 0}) -- angle between g and -y_hat (vertical axis)

	local absolute_hspd = vec.proj_plane(v, {0, 1, 0}) -- hspd along horizontal plane

	if vec.mag(absolute_hspd) ~= 0 then -- only update when possible

		-- angle between hspd and x_hat (choice of x_hat, z_hat is arbitrary)
		yaw = vec.angle({1, 0, 0}, absolute_hspd)

		-- get which side of x-axis it is
		dir = vec.proj(absolute_hspd, {0, 0, 1}).dir
		if dir == -1 then
			yaw = 2 * math.pi - yaw
		end
	end

	if goal_angle == nil then
		return {math.deg(yaw), math.deg(pitch), 0}
	else
		return {math.deg(yaw), math.deg(pitch), math.deg(yaw) - goal_angle}
	end
end

function getAngleText(v, goal_angle, goal_point)
	local angles = getAngle(v, goal_angle)

	if goal_angle ~= nil then
		return string.format("\n==== Angle ====\nYaw:   %4.3f (%.3f)\nPitch: %4.3f\n", angles[1], angles[3], angles[2])
	elseif goal_point ~= nil then
		local desired_v = vec.minus(goal_point, {core.Pos().X, core.Pos().Y, core.Pos().Z})
		local desired_angle = getAngle(desired_v)
		return string.format("\n==== Angle ====\nYaw:   %4.3f (%.3f)\nPitch: %4.3f\n", angles[1], desired_angle[1], angles[2])
	else
		return string.format("\n==== Angle ====\nYaw:   %4.3f\nPitch: %4.3f\n", angles[1], angles[2])
	end
end

-- TODO: max relative height (max jump height = max(vec.proj(jump_dist, ugrav)))
local jump_start_pos = {0, 0, 0}
local jump_end_pos = {0, 0, 0}
local max_jump_height = 0
local previous_state = "-1"
function jumpDistance()
	local jump_vec = {0, 0, 0}

	-- 1 means on ground, 0 means in air (not always accurate during walking transitions?)
	local state = core.StateATable()[2]

	-- ground to air, set start point
	if previous_state == "1" and state == "0" then
		jump_start_pos = {core.PrevPos().X, core.PrevPos().Y, core.PrevPos().Z}
		jump_end_pos = {core.Pos().X, core.Pos().Y, core.Pos().Z}
		max_jump_height = 0

	-- air to ground, set end point
	elseif previous_state == "0" and state == "1" then
		jump_end_pos = {core.Pos().X, core.Pos().Y, core.Pos().Z}

	-- air to air, update latest pos
	elseif previous_state == "0" and state == "0" then
		jump_end_pos = {core.Pos().X, core.Pos().Y, core.Pos().Z}
	end
	-- don't update when staying on ground to see the last jump dist
	previous_state = state

	local jump_vec = vec.minus(jump_end_pos, jump_start_pos) -- difference
	local dist = vec.mag(jump_vec)

	local dgrav = {core.DownGravity().X, core.DownGravity().Y, core.DownGravity().Z}
	local hdist = vec.hspd(jump_vec, dgrav) -- horizontal component

	local ugrav = {core.UpGravity().X, core.UpGravity().Y, core.UpGravity().Z}
	max_jump_height = math.max(vec.yspd(jump_vec, ugrav), max_jump_height)

	return string.format("\n==== Jump Stats ====\nhdist: %13.3f\ndist: %14.3f\nMax Height: %8.3f\n", hdist, dist, max_jump_height)
end


local canWriteToFile = false
local file
function openFile()
	file = io.open("data.txt", "w")
	io.output(file)
	local header = "PosX PosY PosZ VelX VelY VelZ GravUpX GravUpY GravUpZ GravDownX GravDownY GravDownZ TiltX TiltY TiltZ\n"
	io.write(header)
	canWriteToFile = true
end

function writeToFile()
	local raw = ""
	raw = raw..core.Pos().X.." "..core.Pos().Y.." "..core.Pos().Z
	raw = raw.." "..core.BaseVelocity().X.." "..core.BaseVelocity().Y.." "..core.BaseVelocity().Z
	raw = raw.." "..core.UpGrav().X.." "..core.UpGrav().Y.." "..core.UpGrav().Z
	raw = raw.." "..core.Gravity().X.." "..core.Gravity().Y.." "..core.Gravity().Z
	raw = raw.." "..core.Tilt().X.." "..core.Tilt().Y.." "..core.Tilt().Z
	io.write(raw.."\n")
end

function onScriptStart()
	MsgBox("Script Opened")
end

function onScriptCancel()
	MsgBox("Script Closed")
	SetScreenText("")
	if canWriteToFile then
		io.close(file)
		MsgBox("File Closed")
	end
end

local function binaryText(val, length)
	local text = ""
	local size = 2 ^ (length - 1)
	while size > 0 do
		text = string.format("%d", val % 2) .. text
		val = val // 2
		if size == 1 then size = 0 end
		size = size / 2
	end
	return text
end

local function displayValueOrdered(title, data, order, format, binarySize)
	local text = "\n".."==== " .. title .. " ====\n"
	local length = 0
	for k,v in pairs(order) do length = length + 1 end
	for i = 1, length do
		if binarySize ~= nil then
			text = text .. order[i] .. ": " .. binaryText(data[order[i]], binarySize) .. "\n"
		elseif format == nil then
			text = text .. order[i] .. ": " .. data[order[i]] .. "\n"
		else
			text = text .. order[i] .. ": " .. string.format(format, data[order[i]]) .. "\n"
		end
	end
	return text
end

local function displayValue(title, data, format)
	local text = "\n"
	if text ~= "" then text = "\n==== " .. title .. " ====\n" end
	for key,value in pairs(data) do
		if format == nil then
			text = text .. key .. ": " .. value .. "\n"
		else
			text = text .. key .. ": " .. string.format(format, value) .. "\n"
		end
	end
	return text
end

local maxheight = -100000000000
local groundheight = 0
function onScriptUpdate()
	local text = ""
	local xyz = {"X", "Y", "Z"}
	local standard = "%12.6f"

	text = text .. string.format("\nStage Time: %.2f", core.StageTime()/60)
	text = text .. string.format("\nTilt Bonus: %.3f", tilt.GetBonus())
	text = text .. "\nGrounded: " .. core.StateATable()[2] .. "\n"

	text = text .. getAngleText({core.BaseVelocity().X, core.BaseVelocity().Y, core.BaseVelocity().Z}, nil, nil)
	text = text .. displayValueOrdered("Position", core.Pos(), xyz, standard)


	local v = {core.Spd().X, core.Spd().Y, core.Spd().Z}
	local g = {core.DownGravity().X, core.DownGravity().Y, core.DownGravity().Z}
	local yspd = vec.yspd(v, g)
	local hspd = vec.hspd(v, g)
	if -0.001 < yspd and yspd < 0.001 then yspd = 0 end -- removes negative zero
	text = text .. displayValueOrdered("Speed", {yspd = yspd, hspd = hspd}, {"yspd", "hspd"}, "%9.3f")
	text = text .. string.format("XYZ:  %9.3f\n", core.Spd().XYZ)

	text = text .. displayValueOrdered("Velocity", core.BaseVelocity(), xyz, "%15.6f")
	

	SetScreenText(text)

	if core.Stick().X == 0 and core.Stick().Y == -1 then
	end

	if canWriteToFile then
		writeToFile()
	end

end

function onStateLoaded()
end

function onStateSaved()
end
