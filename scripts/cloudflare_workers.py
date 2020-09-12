#!/usr/bin/env python
# -*- coding: utf-8 -*-
import re
import requests
import argparse
import json
from datetime import datetime
from datetime import timezone

class cloudflare_workers:
    def __init__( self ):
        self.verbose = True
        self.s = requests.Session()
        self.atok = ''

    def log_in( self, email, password ):

        r = self.s.get('https://www.cloudflare.com/', )

        new_headers = {
            'Referer': 'https://www.cloudflare.com/',
            'User-Agent': 'Mozilla/5.0 (Windows NT 6.1; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/78.0.3904.108 Safari/537.36',
        }
        self.s.headers = { **self.s.headers, **new_headers }
        r = self.s.get('https://dash.cloudflare.com/login', )
        security_token = self.find_between_r( r.text, '"security_token":"', '"}};</script>' )

        post_data = {
            'email': email,
            'password': password,
            'security_token': security_token,
        }
        new_headers = {
            'Referer': 'https://dash.cloudflare.com/',
            'Content-Type': 'application/x-www-form-urlencoded',
        }
        self.s.headers = { **self.s.headers, **new_headers }
        r = self.s.post('https://dash.cloudflare.com/login', data=post_data)
        self.atok = self.find_between_r( r.text, 'window.bootstrap = {"atok":"', '","locale":"' )
        self.cookie = r.cookies['vses2']

    def add_api_token( self ):

        c = {
            'vses2': self.cookie
        }
        r = self.s.get('https://dash.cloudflare.com/api/v4/user', cookies=c)
        data = json.loads( r.text )
        api_user = data['result']['id']
        policy = {'name': 'workers and zones', 'policies': [{'effect': 'allow', 'resources': {'com.cloudflare.api.account.*': '*'}, 'permission_groups': [{'id': 'f7f0eda5697f475c90846e879bab8666'}, {'id': 'e086da7e2179491d91ee5f35b3ca210a'}, {'id': 'c1fde68c7bcc44588cbb6ddbc16d6480'}]}, {'effect': 'allow', 'resources': {'com.cloudflare.api.user.' + api_user: '*'}, 'permission_groups': [{'id': '8acbe5bb0d54464ab867149d7f7cf8ac'}]}, {'effect': 'allow', 'resources': {'com.cloudflare.api.account.zone.*': '*'}, 'permission_groups': [{'id': '28f4b596e7d643029c524985477ae49a'}, {'id': 'e6d2666161e84845a636613608cee8d5'}, {'id': '3030687196b94b638145a3953da2b699'}]}]}
        r = self.s.post('https://dash.cloudflare.com/api/v4/user/tokens', data=json.dumps(policy), cookies=c)
        data = json.loads( r.text )
        return data['result']['value']

    def get_request_count( self, email ):

        new_headers = {
            'Content-Type': 'application/json; charset=UTF-8',
            'Pragma': 'no-cache',
            'Cache-Control': 'no-cache',
            'X-ATOK': self.atok,
        }
        self.s.headers = { **self.s.headers, **new_headers }
        c = {
            'vses2': self.cookie
        }
        r = self.s.get('https://dash.cloudflare.com/api/v4/user/tokens', cookies=c)
        data = json.loads( r.text )
        token_count = data['result_info']['total_count']
        api_token = ''
        if token_count == 0:
            api_token = self.add_api_token()

        index = email.index("@")
        sub_domain = email[:index]
        sub_domain = re.sub("[^0-9a-zA-Z-]+", "-", sub_domain)

        get_data = {
            'status': 'accepted',
        }
        r = self.s.get('https://dash.cloudflare.com/api/v4/memberships', params=get_data, cookies=c)
        data = json.loads( r.text )
        success = data['success']
        if not success:
            print ( json.dumps(data) )
            return False

        account_id = data['result'][0]['account']['id']

        r = self.s.get('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/subdomain', cookies=c)
        data = json.loads( r.text )
        success = data['success']
        if not success:
            r = self.s.get('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/settings', cookies=c)
            data = json.loads( r.text )

            new_headers = {
                'allow-rename': 'true',
            }
            self.s.headers = { **self.s.headers, **new_headers }
            put_data = {
                'subdomain': sub_domain + datetime.now(tz=timezone.utc).strftime('%Y%m%d'),
            }
            r = self.s.put('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/subdomain', data=json.dumps(put_data), cookies=c)
            data = json.loads( r.text )

        get_data = {
            'time_delta': 'all',
            'dimensions': 'status',
            'metrics': 'requestCount',
            'since': datetime.now(tz=timezone.utc).strftime('%Y-%m-%d') + 'T00:00:00.000Z',
        }
        r = self.s.get('https://dash.cloudflare.com/api/v4/accounts/' + account_id + '/workers/analytics/summary', params=get_data, cookies=c)
        data = json.loads( r.text )
        new_info = {
            'api_token': api_token,
        }
        data = { **data, ** new_info}
        print ( json.dumps(data) )

    def get_account_id( self ):

        get_data = {
            'status': 'accepted',
        }
        new_headers = {
            'Content-Type': 'application/json; charset=UTF-8',
            'Pragma': 'no-cache',
            'Cache-Control': 'no-cache',
            'X-ATOK': self.atok,
        }
        self.s.headers = { **self.s.headers, **new_headers }
        c = {
            'vses2': self.cookie
        }
        r = self.s.get('https://dash.cloudflare.com/api/v4/memberships', params=get_data, cookies=c)
        data = json.loads( r.text )
        print ( json.dumps(data) )

    def email_verification( self ):

        new_headers = {
            'Content-Type': 'application/json; charset=UTF-8',
            'Pragma': 'no-cache',
            'Cache-Control': 'no-cache',
            'X-ATOK': self.atok,
        }
        self.s.headers = { **self.s.headers, **new_headers }
        c = {
            'vses2': self.cookie
        }
        r = self.s.delete('https://dash.cloudflare.com/api/v4/user/email-verification', cookies=c)
        data = json.loads( r.text )
        print ( json.dumps(data) )

    def get_api_token( self, email ):

        c = {
            'vses2': self.cookie
        }
        new_headers = {
            'Content-Type': 'application/json; charset=UTF-8',
            'Pragma': 'no-cache',
            'Cache-Control': 'no-cache',
            'X-ATOK': self.atok,
        }
        self.s.headers = { **self.s.headers, **new_headers }
        api_token = self.add_api_token()

        index = email.index("@")
        sub_domain = email[:index]
        sub_domain = re.sub("[^0-9a-zA-Z-]+", "-", sub_domain)

        get_data = {
            'status': 'accepted',
        }
        r = self.s.get('https://dash.cloudflare.com/api/v4/memberships', params=get_data, cookies=c)
        data = json.loads( r.text )
        success = data['success']
        if not success:
            return False

        account_id = data['result'][0]['account']['id']

        r = self.s.get('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/subdomain', cookies=c)
        data = json.loads( r.text )
        success = data['success']
        if not success:
            r = self.s.get('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/settings', cookies=c)
            data = json.loads( r.text )

            new_headers = {
                'allow-rename': 'true',
            }
            self.s.headers = { **self.s.headers, **new_headers }
            put_data = {
                'subdomain': sub_domain + datetime.now(tz=timezone.utc).strftime('%Y%m%d'),
            }
            r = self.s.put('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/subdomain', data=json.dumps(put_data), cookies=c)
            data = json.loads( r.text )

        print ( api_token )

    def add_subdomain( self, email ):

        c = {
            'vses2': self.cookie
        }
        new_headers = {
            'Content-Type': 'application/json; charset=UTF-8',
            'Pragma': 'no-cache',
            'Cache-Control': 'no-cache',
            'X-ATOK': self.atok,
        }
        self.s.headers = { **self.s.headers, **new_headers }

        index = email.index("@")
        sub_domain = email[:index]
        sub_domain = re.sub("[^0-9a-zA-Z-]+", "-", sub_domain)

        get_data = {
            'status': 'accepted',
        }
        r = self.s.get('https://dash.cloudflare.com/api/v4/memberships', params=get_data, cookies=c)
        data = json.loads( r.text )
        success = data['success']
        if not success:
            return False

        account_id = data['result'][0]['account']['id']

        r = self.s.get('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/subdomain', cookies=c)
        data = json.loads( r.text )
        success = data['success']
        if not success:
            r = self.s.get('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/settings', cookies=c)
            data = json.loads( r.text )

            new_headers = {
                'allow-rename': 'true',
            }
            self.s.headers = { **self.s.headers, **new_headers }
            put_data = {
                'subdomain': sub_domain + datetime.now(tz=timezone.utc).strftime('%Y%m%d'),
            }
            r = self.s.put('https://dash.cloudflare.com/api/v4/accounts/' + account_id +'/workers/subdomain', data=json.dumps(put_data), cookies=c)
            data = json.loads( r.text )
            success = data['success']
            if not success:
                print ( 'error' )
            else:
                print ( 'ok' )
        else:
            print ( 'error' )

    def find_between_r( self, s, first, last ):
        try:
            start = s.rindex( first ) + len( first )
            end = s.rindex( last, start )
            return s[start:end]
        except ValueError:
            return ""

if __name__ == "__main__":
        parser = argparse.ArgumentParser(description='process cloudflare workers.')
        parser.add_argument("-e", "--email", help="cloudflare account email", required=True)
        parser.add_argument("-p", "--password", help="cloudflare account password", required=True)
        parser.add_argument("-o", "--option", help="cloudflare workers option", required=True)
        args = parser.parse_args()

        cloud = cloudflare_workers()
        cloud.log_in( args.email, args.password )
        if args.option == "request_count":
            cloud.get_request_count( args.email )
        else:
            if args.option == "account_id":
                cloud.get_account_id()
            else:
                if args.option == "api_token":
                    cloud.get_api_token( args.email )
                else:
                    if args.option == "add_subdomain":
                        cloud.add_subdomain( args.email )

