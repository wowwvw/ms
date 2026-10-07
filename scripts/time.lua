require "lib.moonloader"

local id = 222

function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then return end
	while not isSampAvailable() do wait(100) end
	sampTextdrawCreate(id, "", 37, 430)
	sampTextdrawSetLetterSizeAndColor(id, 0.3, 1.7, 0xFFff6347)
	sampTextdrawSetOutlineColor(id, 0.5, 0xFF000000)
	sampTextdrawSetAlign(id, 1)
	sampTextdrawSetStyle(id, 2)
	while true do
		sampTextdrawSetString(id, os.date("%H:%M:%S"))
		wait(500)
	end
end
