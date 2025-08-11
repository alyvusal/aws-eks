#!/usr/bin/env python3

import argparse
import socket
import certifi
from OpenSSL import SSL
from eks_oidc.logger import Logger

logger = Logger(__name__).get_logger()


class ThumbNail:
    """Generate CA thumbprint (SHA1 fingerprint of the root CA certificate)."""

    def __init__(self, url: str):
        self._url = url
        self._hostname = self._parse_hostname(url)
        self._cert_chain_fingerprints = []
        self._thumbprint = ""

        try:
            self._fetch_cert_chain()
        except Exception as e:
            logger.exception("Error fetching certificate chain: %s", repr(e))
            raise

    def _parse_hostname(self, url: str) -> str:
        try:
            return url.split("/")[2]
        except IndexError:
            logger.error("Invalid URL format: %s", url)
            raise ValueError("Invalid URL format")

    def _fetch_cert_chain(self) -> None:
        port = 443
        context = SSL.Context(SSL.TLS_CLIENT_METHOD)
        context.load_verify_locations(cafile=certifi.where())

        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        conn = SSL.Connection(context, sock)
        conn.set_tlsext_host_name(self._hostname.encode())
        conn.settimeout(5)
        conn.connect((self._hostname, port))
        conn.setblocking(1)
        conn.do_handshake()

        for idx, cert in enumerate(conn.get_peer_cert_chain()):
            fingerprint = cert.digest("sha1").decode("utf-8").replace(":", "").lower()
            logger.debug(f"{idx} subject: {cert.get_subject()}")
            logger.debug(f"  issuer: {cert.get_issuer()}")
            logger.debug(f"  fingerprint: {fingerprint}")
            self._cert_chain_fingerprints.append(fingerprint)

        conn.close()

        if not self._cert_chain_fingerprints:
            raise RuntimeError("No certificates found in the chain")

        self._thumbprint = self._cert_chain_fingerprints[-1]

    def get_thumbprint(self) -> str:
        return self._thumbprint


def main():
    parser = argparse.ArgumentParser(description="Get root CA SHA1 thumbprint from OIDC URL")
    parser.add_argument("url", help="OIDC issuer URL (e.g., https://oidc.eks.us-east-1.amazonaws.com/id/XYZ...)")
    args = parser.parse_args()

    try:
        thumb = ThumbNail(args.url)
        print(thumb.get_thumbprint())
    except Exception as e:
        logger.error("Failed to get thumbprint: %s", str(e))
        exit(1)


if __name__ == "__main__":
    main()
