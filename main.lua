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
local plugPath = path .. "/plugins/filebrowser.koplugin/filebrowser"
local binPath = plugPath .. "/filebrowser"
local logPath = plugPath .. "/filebrowser.log"
local pidFilePath = "/tmp/filebrowser_koreader.pid"

if not util.pathExists(binPath) or os.execute("start-stop-daemon") == 127 then
    return { disabled = true, }
end

local Filebrowser = WidgetContainer:extend {
    name = "Filebrowser",
    is_doc_only = false,
}

function Filebrowser:init()
    self.filebrowser_port = G_reader_settings:readSetting("filebrowser_port") or "80"
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function Filebrowser:start()
    -- Since Filebrowser doesn't start as a deamon by default and has no option to
    -- set a pidfile, we launch it using the start-stop-daemon helper. On Kobo and Kindle,
    -- this command is provided by BusyBox:
    -- https://busybox.net/downloads/BusyBox.html#start_stop_daemon
    -- The full version has slightly more options, but seems to be a superset of
    -- the BusyBox version, so it should also work with that:
    -- https://man.cx/start-stop-daemon(8)

    -- Use a pidfile to identify the process later, set --oknodo to not fail if
    -- the process is already running and set --background to start as a
    -- background process. On Filebrowser itself, set the root directory,
    -- and a log file.
    local cmd = string.format(
        "start-stop-daemon -S "
        .. "--make-pidfile --pidfile %s " -- pidFilePath
        .. "--oknodo "
        .. "--background "
        .. "--exec %s " -- binPath
        .. "-- "
        .. "-a 0.0.0.0 "
        .. "-r %s " -- dataPath
        .. "-p %s " -- filebrowser_port
        .. "-l %s", -- logPath
        pidFilePath,
        binPath,

        dataPath,
        self.filebrowser_port,
        logPath
    )

    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
    logger.dbg("[Filebrowser] Opening port: ", filebrowser_port)
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.filebrowser_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.filebrowser_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    logger.dbg("[Filebrowser] Launching Filebrowser: ", cmd)

    local status = os.execute(cmd)
    if status == 0 then
        logger.dbg("[Filebrowser] Filebrowser started. Find Filebrowser logs at ", logPath)
        local info = InfoMessage:new {
            timeout = 2,
            text = _("Filebrowser started.")
        }
        UIManager:show(info)
    else
        logger.dbg("[Filebrowser] Failed to start Filebrowser, status: ", status)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to start Filebrowser."),
        }
        UIManager:show(info)
    end
end

function Filebrowser:isRunning()
    -- Use start-stop-daemon -K (to stop a process) in --test mode to find if
    -- there are any matching processes for this pidfile and executable. If
    -- there are any matching processes, this exits with status code 0.
    local cmd = string.format(
        "start-stop-daemon --pidfile %s --exec %s -K --test",
        pidFilePath,
        binPath
    )

    logger.dbg("[Filebrowser] Check if Filebrowser is running: ", cmd)
    
    local status = os.execute(cmd)

    logger.dbg("[Filebrowser] Running status exit code (0 -> running): ", status)

    return status == 0
end

function Filebrowser:stop()
    -- Use start-stop-daemon -K to stop the process, with --oknodo to exit with
    -- status code 0 if there are no matching processes in the first place.
    local cmd = string.format(
        "start-stop-daemon --pidfile %s --exec %s --oknodo -K",
        pidFilePath,
        binPath
    )

    logger.dbg("[Filebrowser] Stopping Filebrowser: ", cmd)

    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
    logger.dbg("[Filebrowser] Closing port: ", filebrowser_port)
        os.execute(string.format("%s %s %s",
            "iptables -D INPUT -p tcp --dport", self.SSH_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -D OUTPUT -p tcp --sport", self.SSH_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end
    local status = os.execute(cmd)
    if status == 0 then
        logger.dbg("[Filebrowser] Filebrowser stopped.")

        UIManager:show(InfoMessage:new {
            text = _("Filebrowser stopped!"),
            timeout = 2,
        })

        if util.pathExists(pidFilePath) then
            logger.dbg("[Filebrowser] Removing PID file at ", pidFilePath)
            os.remove(pidFilePath)
        end
    else
        logger.dbg("[Filebrowser] Failed to stop Filebrowser, status: ", status)

        UIManager:show(InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to stop Filebrowser.")
        })
    end  
end

function Filebrowser:onToggleFilebrowser()
    if self:isRunning() then
        self:stop()
    else
        self:start()
    end
end

function Filebrowser:addToMainMenu(menu_items)
    menu_items.filebrowser = {
        text = _("Filebrowser"),
        sorting_hint = "network",
        keep_menu_open = true,
        checked_func = function() return self:isRunning() end,
        callback = function(touchmenu_instance)
            self:onToggleFilebrowser()
            -- sleeping might not be needed, but it gives the feeling
            -- something has been done and feedback is accurate
            ffiutil.sleep(1)
            touchmenu_instance:updateItems()
        end,
    }
end

function Filebrowser:onDispatcherRegisterActions()
    Dispatcher:registerAction("toggle_filebrowser",
        { category = "none", event = "ToggleFilebrowser", title = _("Toggle Filebrowser"), general = true })
end

return Filebrowser
