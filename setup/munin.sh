#!/bin/bash
# Munin: resource monitoring tool
#################################################

source setup/functions.sh # load our functions
source /etc/mailinabox.conf # load global vars

# install Munin
echo "Installing Munin (system monitoring)..."
apt_install munin munin-node libcgi-fast-perl
# libcgi-fast-perl is needed by /usr/lib/munin/cgi/munin-cgi-graph

# edit config
cat > /etc/munin/munin.conf <<EOF;
dbdir /var/lib/munin
htmldir /var/cache/munin/www
logdir /var/log/munin
rundir /var/run/munin
tmpldir /etc/munin/templates

includedir /etc/munin/munin-conf.d

# path dynazoom uses for requests
cgiurl_graph /admin/munin/cgi-graph

# a simple host tree
[$PRIMARY_HOSTNAME]
address 127.0.0.1

# send alerts to the following address
contacts admin
contact.admin.command mail -s "Munin notification \${var:host}" administrator@$PRIMARY_HOSTNAME
contact.admin.always_send warning critical
EOF

# The Debian installer touches these files and chowns them to www-data:adm for use with spawn-fcgi
chown munin /var/log/munin/munin-cgi-html.log
chown munin /var/log/munin/munin-cgi-graph.log

# ensure munin-node knows the name of this machine
# and reduce logging level to warning
tools/editconf.py /etc/munin/munin-node.conf -s \
    host_name="$PRIMARY_HOSTNAME" \
    log_level=1

# Update the activated plugins through munin's autoconfiguration.
munin-node-configure --shell --remove-also 2>/dev/null | sh || /bin/true
echo "node Munin (system monitoring)..."

# Deactivate monitoring of NTP peers.
find /etc/munin/plugins/ -lname /usr/share/munin/plugins/ntp_ -print0 | xargs -0 /bin/rm -f

# Deactivate monitoring of network interfaces that are not up.
for f in $(find /etc/munin/plugins/ \( -lname /usr/share/munin/plugins/if_ -o -lname /usr/share/munin/plugins/if_err_ -o -lname /usr/share/munin/plugins/bonding_err_ \)); do
    IF=$(echo "$f" | sed s/.*_//);
    if ! grep -qFx up "/sys/class/net/$IF/operstate" 2>/dev/null; then
        rm "$f";
    fi;
done

# Create a 'state' directory. Not sure why we need to do this manually.
mkdir -p /var/lib/munin-node/plugin-state/

# Install and configure Supervisor.
# apt_install supervisor

# Create Supervisor configuration for Munin
cat > /etc/supervisor/conf.d/munin.conf <<EOF
[program:munin-cron]
command=/usr/bin/munin-cron
user=munin
autostart=true
autorestart=true
stderr_logfile=/var/log/munin/munin-cron.err.log
stdout_logfile=/var/log/munin/munin-cron.out.log

[program:munin-node]
command=/usr/sbin/munin-node
user=munin
autostart=true
autorestart=true
stderr_logfile=/var/log/munin/munin-node.err.log
stdout_logfile=/var/log/munin/munin-node.out.log
EOF

# Reload Supervisor configuration and start services
supervisorctl reread
supervisorctl update
supervisorctl start munin-cron
supervisorctl start munin-node

# Generate initial statistics so the directory isn't empty
# Check to see if munin-cron is already running
if [ ! -f /var/run/munin/munin-update.lock ]; then
    sudo -H -u munin munin-cron
fi
