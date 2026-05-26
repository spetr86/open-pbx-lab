; LAN-only lab defaults. Do not expose directly to the public internet.
[global]
type=global
user_agent=${ASTERISK_SITE_NAME}
endpoint_identifier_order=auth_username,username,ip

[transport-udp]
type=transport
protocol=udp
bind=${ASTERISK_LISTEN_IP}:${ASTERISK_SIP_PORT}
local_net=${ASTERISK_LOCAL_NET}
external_media_address=${ASTERISK_ADVERTISED_IP}
external_signaling_address=${ASTERISK_ADVERTISED_IP}

[${ASTERISK_EXT_A_NUMBER}]
type=endpoint
transport=transport-udp
context=internal
disallow=all
allow=ulaw,alaw
allow_subscribe=no
auth=${ASTERISK_EXT_A_NUMBER}-auth
aors=${ASTERISK_EXT_A_NUMBER}
direct_media=no
force_rport=yes
rewrite_contact=yes
rtp_symmetric=yes
trust_id_inbound=no
trust_id_outbound=no
send_pai=no
send_rpid=no
contact_deny=0.0.0.0/0.0.0.0
contact_permit=${ASTERISK_ENDPOINT_CONTACT_CIDR}

[${ASTERISK_EXT_A_NUMBER}-auth]
type=auth
auth_type=userpass
username=${ASTERISK_EXT_A_NUMBER}
password=${ASTERISK_EXT_A_PASSWORD}

[${ASTERISK_EXT_A_NUMBER}]
type=aor
max_contacts=1
remove_existing=yes

[${ASTERISK_EXT_B_NUMBER}]
type=endpoint
transport=transport-udp
context=internal
disallow=all
allow=ulaw,alaw
allow_subscribe=no
auth=${ASTERISK_EXT_B_NUMBER}-auth
aors=${ASTERISK_EXT_B_NUMBER}
direct_media=no
force_rport=yes
rewrite_contact=yes
rtp_symmetric=yes
trust_id_inbound=no
trust_id_outbound=no
send_pai=no
send_rpid=no
contact_deny=0.0.0.0/0.0.0.0
contact_permit=${ASTERISK_ENDPOINT_CONTACT_CIDR}

[${ASTERISK_EXT_B_NUMBER}-auth]
type=auth
auth_type=userpass
username=${ASTERISK_EXT_B_NUMBER}
password=${ASTERISK_EXT_B_PASSWORD}

[${ASTERISK_EXT_B_NUMBER}]
type=aor
max_contacts=1
remove_existing=yes
