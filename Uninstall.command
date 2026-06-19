#!/bin/sh
#
# PaperCut Print Deploy Client Uninstall Script
#
agreed=
answered=

if [ "$1" == "-y" ]; then
    agreed=1
    answered=1
fi

while [ -z "${answered}" ]; do
        echo
        echo
        echo "Would you like to uninstall PaperCut Print Deploy Client?  [yes or no] "
        read reply leftover
        case $reply in
            [yY] | [yY][eE][sS])
                agreed=1
                answered=1
                ;;
            [nN] | [nN][oO])
                answered=1
                read
                ;;
        esac
done
if [ ! -z "${agreed}" ]; then

    if [ "${USER}" != "root" ]; then
        echo "You must be an administrator user to run this program."
        echo "Enter your password if requested..."
    fi

    sudo sh -c "(
        if [ -f '/Applications/PaperCut Print Deploy Client/direct-print-monitor/Uninstall.command' ]; then
            echo 'Uninstalling Direct print monitor...'
            #
            # Stop and disable direct print monitor services
            #
            '/Applications/PaperCut Print Deploy Client/direct-print-monitor/Uninstall.command'
            sleep 5
        fi
        echo 'Uninstalling...'
        #
        # Stop and disable services
        #
        '/Applications/PaperCut Print Deploy Client/pc-print-deploy-client' uninstall

        sleep 5

        #
        # Remove startup entry
        #
        rm -rf /Library/LaunchAgents/com.papercut.printdeploy.client.plist

        #
        # Execute the uninitialise script
        #
        '/Applications/PaperCut Print Deploy Client/uninitialise'

        #
        # Remove files install... Note: we only remove files that we've put in
        # our top directory.
        #
        rm -rf '/Applications/PaperCut Print Deploy Client'

        #
        # Remove the install receipt reference which the Mac uses to know what packages are installed.
        # If these are not removed then the mac can block us from installing previous versions
        #
        rm -f /private/var/db/receipts/com.papercut.printdeploy.client.*  2>/dev/null
    )"
    echo "Uninstall complete."
fi
