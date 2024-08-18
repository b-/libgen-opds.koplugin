-- set to the root directory you want to manage
-- on Kindle this should probably be:
-- local dataPath = "/mnt/us"
local dataPath = "/"

local BD = require("ui/bidi")
local DataStorage = require("datastorage")
local Device =  require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")  -- luacheck:ignore
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local logger = require("logger")
local util = require("util")
local _ = require("gettext")
local T = ffiutil.template

local path = DataStorage:getFullDataDir()
local plugPath = path .. "/plugins/libgen-opds.koplugin/libgen-opds"
local binPath = plugPath .. "/libgen-opds"
local logPath = plugPath .. "/libgen-opds.log"
local pidFilePath = "/tmp/libgen-opds_koreader.pid"

if not util.pathExists(binPath) or os.execute("start-stop-daemon") == 127 then
    return { disabled = true, }
end

local libgen_opds = WidgetContainer:extend {
    name = "libgen_opds",
    is_doc_only = false,
}

function libgen_opds:init()
    self.libgen_opds_user = G_reader_settings:readSetting("libgen_opds_user") or "user"
    self.libgen_opds_pass = G_reader_settings:readSetting("libgen_opds_pass") or "pass"
    self.libgen_opds_port = G_reader_settings:readSetting("libgen_opds_port") or "5144"
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function libgen_opds:start()
    -- Since libgen_opds doesn't start as a daemon by default and has no option to
    -- set a pidfile, we launch it using the start-stop-daemon helper. On Kobo and Kindle,
    -- this command is provided by BusyBox:
    -- https://busybox.net/downloads/BusyBox.html#start_stop_daemon
    -- The full version has slightly more options, but seems to be a superset of
    -- the BusyBox version, so it should also work with that:
    -- https://man.cx/start-stop-daemon(8)

    -- Use a pidfile to identify the process later, set --oknodo to not fail if
    -- the process is already running and set --background to start as a
    -- background process. On libgen_opds itself, set the root directory,
    -- and a log file.
    local cmd = string.format(
        "start-stop-daemon -S "
        .. "--make-pidfile --pidfile %s " -- pidFilePath
        .. "--oknodo "
        .. "--background "
        .. "--startas /usr/bin/env API_USERNAME=user API_PASSWORD=pass " -- libgen_opds_user, libgen_opds_pass
        .. "%s " -- binPath
        .. "-- "
        .. "serve",
        pidFilePath,
        binPath
    )


    logger.dbg("[libgen_opds] Launching libgen_opds: ", cmd)

    local status = os.execute(cmd)
    if status == 0 then
        logger.dbg("[libgen_opds] libgen_opds started. Find libgen_opds logs at ", logPath)
        local info = InfoMessage:new {
            timeout = 2,
            text = _("libgen_opds started.")
        }
        UIManager:show(info)
    else
        logger.dbg("[libgen_opds] Failed to start libgen_opds, status: ", status)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to start libgen_opds."),
        }
        UIManager:show(info)
    end
end

function libgen_opds:isRunning()
    -- Use start-stop-daemon -K (to stop a process) in --test mode to find if
    -- there are any matching processes for this pidfile and executable. If
    -- there are any matching processes, this exits with status code 0.
    local cmd = string.format(
        "start-stop-daemon --pidfile %s --exec %s -K --test",
        pidFilePath,
        binPath
    )

    logger.dbg("[libgen_opds] Check if libgen_opds is running: ", cmd)
    
    local status = os.execute(cmd)

    logger.dbg("[libgen_opds] Running status exit code (0 -> running): ", status)

    return status == 0
end

function libgen_opds:stop()
    -- Use start-stop-daemon -K to stop the process, with --oknodo to exit with
    -- status code 0 if there are no matching processes in the first place.
    local cmd = string.format(
        "start-stop-daemon --pidfile %s --exec %s --oknodo -K",
        pidFilePath,
        binPath
    )

    logger.dbg("[libgen_opds] Stopping libgen_opds: ", cmd)

    local status = os.execute(cmd)
    if status == 0 then
        logger.dbg("[libgen_opds] libgen_opds stopped.")

        UIManager:show(InfoMessage:new {
            text = _("libgen_opds stopped!"),
            timeout = 2,
        })

        if util.pathExists(pidFilePath) then
            logger.dbg("[libgen_opds] Removing PID file at ", pidFilePath)
            os.remove(pidFilePath)
        end
    else
        logger.dbg("[libgen_opds] Failed to stop libgen_opds, status: ", status)

        UIManager:show(InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to stop libgen_opds.")
        })
    end  
end

function libgen_opds:onTogglelibgen_opds()
    if self:isRunning() then
        self:stop()
    else
        self:start()
    end
end

function libgen_opds:addToMainMenu(menu_items)
    menu_items.libgen_opds = {
        text = _("libgen_opds"),
        sorting_hint = "network",
        keep_menu_open = true,
        checked_func = function() return self:isRunning() end,
        callback = function(touchmenu_instance)
            self:onTogglelibgen_opds()
            -- sleeping might not be needed, but it gives the feeling
            -- something has been done and feedback is accurate
            ffiutil.sleep(1)
            touchmenu_instance:updateItems()
        end,
    }
end

function libgen_opds:onDispatcherRegisterActions()
    Dispatcher:registerAction("toggle_libgen_opds",
        { category = "none", event = "Togglelibgen_opds", title = _("Toggle libgen_opds"), general = true })
end

return libgen_opds

