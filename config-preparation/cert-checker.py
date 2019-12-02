import sys
import os
import time
from OpenSSL import crypto
from datetime import datetime


def getCertInfo(certLocation):
    out = {}
    certF=open(certLocation, 'rt').read()
    cert = crypto.load_certificate(crypto.FILETYPE_PEM, certF)
    subject = cert.get_subject()
    out['subject'] = "".join("/{0:s}={1:s}".format(name.decode(), value.decode()) for name, value in subject.get_components())
    out['notAfter'] = int(time.mktime(datetime.strptime(str(cert.get_notAfter()), '%Y%m%d%H%M%SZ').timetuple()))
    out['notBefore'] = int(time.mktime(datetime.strptime(str(cert.get_notBefore()), '%Y%m%d%H%M%SZ').timetuple()))
    out['issuer'] = "".join("/{0:s}={1:s}".format(name.decode(), value.decode()) for name, value in cert.get_issuer().get_components())
    out['fullDN'] = "%s%s" % (out['issuer'], out['subject'])
    print 'Cert Info: %s' % out
    print 'Certificate Subject:     ', out['subject']
    print 'Certificate Valid From:  ', out['notAfter']
    print 'Certificate Valid Until: ', out['notBefore']
    print 'Certificate Issuer:      ', out['issuer']
    print 'Certificate Full DN:     ', out['fullDN']
    print '-'*80
    print 'INFO: Please ensure that Certificate full DN is entered to /etc/dtnrm-auth.conf file.'
    print '-'*80

if __name__ == '__main__':
    print sys.argv
    getCertInfo(sys.argv[1])
