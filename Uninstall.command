#!/bin/sh
#
# PaperCut Print Deploy Client Uninstall Script
#
        #
        # Stop and disable services
        #
        launchctl unload -w /Library/LaunchDaemons/papercut-event-monitor.plist
        sleep 5

        #
        # Delete our host user account
        #
        sudo dscl . delete /users/papercut

        #
        # Remove any CUPS prefixes
        #
        '/Applications/PaperCut Print Deploy Client/direct-print-monitor/providers/print/mac/configure-cups' remove-all >/dev/null 2>&1

        #
        # Remove any files created outside our install directory.
        #
        rm -f /etc/print-provider.conf
        rm -f /usr/libexec/cups/backend/papercut
        rm -f /usr/libexec/cups/filter/papercut
        rm -f /Library/LaunchDaemons/papercut-event-monitor.plist
        rm -fr '/Library/Application Support/PaperCut/Print Provider'
        # Remove directory if empty, ignore errors
        rmdir '/Library/Application Support/PaperCut' || true

        #
        # Remove files install... Note: we only remove files that we've put in
        # our top directory.
        #
        rm -fr '/Applications/PaperCut Print Deploy Client/direct-print-monitor/providers'
        rm -fr '/Applications/PaperCut Print Deploy Client/direct-print-monitor/.oracle_jre_usage'
        rm -f  '/Applications/PaperCut Print Deploy Client/direct-print-monitor/Uninstall.command'
        rm -f  '/Applications/PaperCut Print Deploy Client/direct-print-monitor/Configure CUPS.command'
        rm -f  '/Applications/PaperCut Print Deploy Client/direct-print-monitor/Control Printer Monitoring.command'
        rm -f  '/Applications/PaperCut Print Deploy Client/direct-print-monitor/THIRDPARTYLICENSEREADME.txt'

        #
        # Remove the install directory if empty
        #
        rmdir '/Applications/PaperCut Print Deploy Client/direct-print-monitor' 2>/dev/null

        #
        # Remove the install receipt reference which the Mac uses to know what packages are installed.
        # If these are not removed then the mac can block us from installing previous versions
        #
        rm -f /private/var/db/receipts/com.papercut.printdeploy.provider.*  2>/dev/null


    echo "DPM Uninstall complete."

