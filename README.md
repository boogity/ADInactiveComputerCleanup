**Script should be automated to run with a dedicated AD cleanup service account**

Automatically disable computers in AD's Student Affairs OU after 120 days with no logon and add a description showing the disabled date. After 180 days with no activity or re-enabling (+60 days from the date of initial disable, logic checks to verify only looks for disabled machines) it will move these computers to the To Be Deleted OU. 

The DisableComputers function of the script will leave machines in the same OU but disable them and add the description, "Computer disabled for inactivity on $today" to them. See disabledComputers.xlsx for the list of computers that will be disabled on our first run of the script. 

The ComputersToBeDeleted function of the script will *not* delete any objects from AD, at least for the first several months, if ever. Instead the current plan is to automate moving them to the "To Be Deleted OU" and having a level 2 look them over once a week/month/some-interval-to-be-determined and manually delete them from AD after verifying there are no servers or other false positives.
