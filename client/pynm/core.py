import configparser
import os
import sys
import re

import requests

class netmagis:
    def __init__ (self, configfile, trace=False):
        self._url = None
        self._key = None
        self._domains = None
        self._views = None
        self._hinfos = None
        self._dhcpprofiles = None
        self._trace = trace

        gf = '%ETCDIR%/netmagisrc'
        if configfile is None:
            lf = os.path.expanduser ('~') + '/.config/netmagisrc'
        else:
            lf = configfile

        self._config = configparser.ConfigParser (interpolation=None)

        if not self._config.read ([gf, lf]):
            self.grmbl ('No configuration file found (neither {} nor {})'.
                                                        format (gf, lf))

        self._url = self.getconf ('general', 'url')
        self._key = self.getconf ('general', 'key')

    def getconf (self, section, key):
        try:
            v = self._config.get (section, key)
        except (configparser.NoOptionError, configparser.NoSectionError) as m:
            self.grmbl ('Configuration file: ' + str (m))
        return v

    def api (self, verb, url, params=None, json=None, check=True):
        url = self._url + url
        cookies = {'session': self._key}
        if self._trace:
            print ('\n{} {} cookies={} params={} json={}'
                        .format (verb, url, cookies, params, json),
                        file=sys.stderr)
        r = requests.request (verb, url, cookies=cookies, params=params, json=json)
        if self._trace:
            print ('{} {}\n{}'.format (r.status_code, r.reason, r.text),
                        file=sys.stderr)
        # XXX : check if not authenticated or other non-api errors
        # (server not found, ...)
        if check and r.status_code != 200:
            self.grmbl ('Server error {} ({})'.format (r.status_code, r.reason))
        return r

    def _read_domains (self):
        res = self.api ('get', '/domains')
        return res.json ()

    def get_iddom (self, name):
        if self._domains is None:
            self._domains = self._read_domains ()
        iddom = None
        for j in self._domains:
            if j ['name'] == name:
                iddom = j ['iddom']
                break
        return iddom

    def _read_views (self):
        res = self.api ('get', '/views')
        return res.json ()

    def get_idview (self, name):
        if self._views is None:
            self._views = self._read_views ()
        idview = None
        for j in self._views:
            if j ['name'] == name:
                idview = j ['idview']
                break
        return idview

    def _read_hinfos (self):
        res = self.api ('get', '/hinfos')
        return res.json ()

    def get_idhinfo (self, name, present=True):
        if self._hinfos is None:
            self._hinfos = self._read_hinfos ()
        idhinfo = None
        for j in self._hinfos:
            if j ['name'] == name:
                if not (present and j ['present'] == 0):
                    idhinfo = j ['idhinfo']
                break
        return idhinfo

    def _read_dhcpprofiles (self):
        res = self.api ('get', '/dhcpprofiles')
        return res.json ()

    def get_iddhcpprofile (self, name):
        if self._dhcpprofiles is None:
            self._dhcpprofiles = self._read_dhcpprofiles ()
        iddhcpprof = None
        for j in self._dhcpprofiles:
            if j ['name'] == name:
                iddhcpprof = j ['iddhcpprof']
                break
        return iddhcpprof

    def split_fqdn (self, fqdn, view):
        m = re.match (r'^([^.]+)\.(.+)', fqdn)
        if m is None:
            self.grmbl ("Invalid FQDN '{}'".format (fqdn))
        (local, domain) = m.groups ()
        iddom = self.get_iddom (domain)
        if iddom is None:
            self.grmbl ("Invalid domain '{}'".format (domain))
        idview = self.get_idview (view)
        if idview is None:
            self.grmbl ("Invalid view '{}'".format (view))
        return (local, domain, iddom, idview)

    def get_host (self, fqdn, view, must_exist=True):
        (name, domain, iddom, idview) = self.split_fqdn (fqdn, view)

        query = {'name': name, 'domain': domain, 'view': view}
        r = self.api ('get', '/hosts', params=query)

        h = None

        j = r.json ()
        nr = len (j)
        if nr == 0:
            if must_exist:
                msg = "Host '{}' does not exist in view {}"
                self.grmbl (msg.format (fqdn, view))
        elif nr == 1:
            h = j [0]
        else:
            # this case should never happen
            msg = "Server error: host '{}' exists more than once in view {}"
            self.grmbl (msg.format (fqdn, view))

        return (name, domain, iddom, idview, h)

    def get_alias (self, fqdn, view, must_exist=True):
        (name, domain, iddom, idview) = self.split_fqdn (fqdn, view)

        query = {'name': name, 'domain': domain, 'view': view}
        r = self.api ('get', '/aliases', params=query)

        a = None

        j = r.json ()
        nr = len (j)
        if nr == 0:
            if must_exist:
                msg = "Alias '{}' does not exist in view {}"
                self.grmbl (msg.format (fqdn, view))
        elif nr == 1:
            a = j [0]
        else:
            # this case should never happen
            msg = "Server error: alias '{}' exists more than once in view {}"
            self.grmbl (msg.format (fqdn, view))

        return (name, domain, iddom, idview, a)

    def get_zone (self, name, view):
        idview = None
        if view is not None:
            idview = self.get_idview (view)
            if not idview:
                self.grmbl ('Unknown view {}'.format (view))

        query = {'name': name}
        if idview:
            query ['idview'] = idview
        for table in ['zone_forward', 'zone_reverse4', 'zone_reverse6']:
            r = self.api ('get', '/admin/dns.' + table, params=query)
            j = r.json ()
            nr = len (j)
            if nr == 1:
                break
            elif nr > 1:
                # this case should never happen
                msg = "Server error: zone '{}' found more than once"
                self.grmbl (msg.format (name))
        else:
            if idview:
                self.grmbl ("Zone {} not found in view {}".format (name, view))
            else:
                self.grmbl ("Zone {} not found".format (name))

        return (table, j [0])

    def grmbl (self, msg):
        print (msg, file=sys.stderr)
        sys.exit (1)
