# recover-workflow.sh
#
# recover workflow for Relax-and-Recover
#
# This file is part of Relax-and-Recover, licensed under the GNU General
# Public License. Refer to the included COPYING for full text of license.

WORKFLOW_recover_DESCRIPTION="recover the system"
WORKFLOWS=( ${WORKFLOWS[@]} recover )
function WORKFLOW_recover () {
    # Adapt /etc/motd in the ReaR recovery system when 'rear recover' is running
    # to avoid the additional 'Run "rear recover" to restore your system !' message
    # that only makes sense as long as 'rear recover' was not ever started,
    # see https://github.com/rear/rear/issues/1433
    # but do not (over)-write /etc/motd on the original system via "rear -s recover",
    # see https://github.com/rear/rear/issues/1670
    # in the ReaR recovery system /etc/rear-release is unique (it does not exist otherwise)
    # cf. init/default/050_check_rear_recover_mode.sh
    test -f /etc/rear-release -a -w /etc/motd && echo -e '\nWelcome to Relax-and-Recover.\n' >/etc/motd

    SourceStage "setup"

    SourceStage "verify"

    SourceStage "layout/prepare"
    SourceStage "layout/recreate"

    SourceStage "restore"

    SourceStage "finalize"
    SourceStage "wrapup"
}

