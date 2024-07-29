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

local libgen-opds = WidgetContainer:extend {
    name = "libgen-opds",
    is_doc_only = false,
}

function libgen-opds:init()
    self.libgen-opds_port = G_reader_settings:readSetting("libgen-opds_port") or "80"
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()
end

function libgen-opds:start()
    -- Since libgen-opds doesn't start as a deamon by default and has no option to
    -- set a pidfile, we launch it using the start-stop-daemon helper. On Kobo and Kindle,
    -- this command is provided by BusyBox:
    -- https://busybox.net/downloads/BusyBox.html#start_stop_daemon
    -- The full version has slightly more options, but seems to be a superset of
    -- the BusyBox version, so it should also work with that:
    -- https://man.cx/start-stop-daemon(8)

    -- Use a pidfile to identify the process later, set --oknodo to not fail if
    -- the process is already running and set --background to start as a
    -- background process. On libgen-opds itself, set the root directory,
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
        .. "-p %s " -- libgen-opds_port
        .. "-l %s", -- logPath
        pidFilePath,
        binPath,

        dataPath,
        self.libgen-opds_port,
        logPath
    )

    -- Make a hole in the Kindle's firewall
    if Device:isKindle() then
    logger.dbg("[libgen-opds] Opening port: ", libgen-opds_port)
        os.execute(string.format("%s %s %s",
            "iptables -A INPUT -p tcp --dport", self.libgen-opds_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -A OUTPUT -p tcp --sport", self.libgen-opds_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end

    logger.dbg("[libgen-opds] Launching libgen-opds: ", cmd)

    local status = os.execute(cmd)
    if status == 0 then
        logger.dbg("[libgen-opds] libgen-opds started. Find libgen-opds logs at ", logPath)
        local info = InfoMessage:new {
            timeout = 2,
            text = _("libgen-opds started.")
        }
        UIManager:show(info)
    else
        logger.dbg("[libgen-opds] Failed to start libgen-opds, status: ", status)
        local info = InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to start libgen-opds."),
        }
        UIManager:show(info)
    end
end

function libgen-opds:isRunning()
    -- Use start-stop-daemon -K (to stop a process) in --test mode to find if
    -- there are any matching processes for this pidfile and executable. If
    -- there are any matching processes, this exits with status code 0.
    local cmd = string.format(
        "start-stop-daemon --pidfile %s --exec %s -K --test",
        pidFilePath,
        binPath
    )

    logger.dbg("[libgen-opds] Check if libgen-opds is running: ", cmd)
    
    local status = os.execute(cmd)

    logger.dbg("[libgen-opds] Running status exit code (0 -> running): ", status)

    return status == 0
end

function libgen-opds:stop()
    -- Use start-stop-daemon -K to stop the process, with --oknodo to exit with
    -- status code 0 if there are no matching processes in the first place.
    local cmd = string.format(
        "start-stop-daemon --pidfile %s --exec %s --oknodo -K",
        pidFilePath,
        binPath
    )

    logger.dbg("[libgen-opds] Stopping libgen-opds: ", cmd)

    -- Plug the hole in the Kindle's firewall
    if Device:isKindle() then
    logger.dbg("[libgen-opds] Closing port: ", libgen-opds_port)
        os.execute(string.format("%s %s %s",
            "iptables -D INPUT -p tcp --dport", self.SSH_port,
            "-m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT"))
        os.execute(string.format("%s %s %s",
            "iptables -D OUTPUT -p tcp --sport", self.SSH_port,
            "-m conntrack --ctstate ESTABLISHED -j ACCEPT"))
    end
    local status = os.execute(cmd)
    if status == 0 then
        logger.dbg("[libgen-opds] libgen-opds stopped.")

        UIManager:show(InfoMessage:new {
            text = _("libgen-opds stopped!"),
            timeout = 2,
        })

        if util.pathExists(pidFilePath) then
            logger.dbg("[libgen-opds] Removing PID file at ", pidFilePath)
            os.remove(pidFilePath)
        end
    else
        logger.dbg("[libgen-opds] Failed to stop libgen-opds, status: ", status)

        UIManager:show(InfoMessage:new {
            icon = "notice-warning",
            text = _("Failed to stop libgen-opds.")
        })
    end  
end

function libgen-opds:onTogglelibgen-opds()
    if self:isRunning() then
        self:stop()
    else
        self:start()
    end
end

function libgen-opds:addToMainMenu(menu_items)
    menu_items.libgen-opds = {
        text = _("libgen-opds"),
        sorting_hint = "network",
        keep_menu_open = true,
        checked_func = function() return self:isRunning() end,
        callback = function(touchmenu_instance)
            self:onTogglelibgen-opds()
            -- sleeping might not be needed, but it gives the feeling
            -- something has been done and feedback is accurate
            ffiutil.sleep(1)
            touchmenu_instance:updateItems()
        end,
    }
end

function libgen-opds:onDispatcherRegisterActions()
    Dispatcher:registerAction("toggle_libgen-opds",
        { category = "none", event = "Togglelibgen-opds", title = _("Toggle libgen-opds"), general = true })
end

return libgen-opds
