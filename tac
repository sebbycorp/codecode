key = "tacacs123"
accounting file = /var/log/tac_plus_acct

# Syslog accounting
accounting syslog

user = tacadmin {
    login = cleartext "admin123"
    pap = cleartext "admin123"
    service = exec {
        priv-lvl = 15
    }
}

user = tacoper {
    login = cleartext "oper123"
    pap = cleartext "oper123"
    service = exec {
        priv-lvl = 1
    }
}
