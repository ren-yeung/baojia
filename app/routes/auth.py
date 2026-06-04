from flask import Blueprint, render_template, redirect, url_for, request, flash, current_app
from flask_login import login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
from app import db
from app.models import User
import requests as http_requests
import time
import urllib.parse

auth_bp = Blueprint('auth', __name__, url_prefix='/auth')

_wework_token_cache = {'token': None, 'expires_at': 0}


def _get_wework_access_token():
    now = time.time()
    if _wework_token_cache['token'] and _wework_token_cache['expires_at'] > now:
        return _wework_token_cache['token']
    corp_id = current_app.config['WEWORK_CORP_ID']
    secret = current_app.config['UEWORK_SECRET']
    url = f'https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid={corp_id}&corpsecret={secret}'
    resp = http_requests.get(url, timeout=10).json()
    if resp.get('errcode') == 0:
        _wework_token_cache['token'] = resp['access_token']
        _wework_token_cache['expires_at'] = now + resp.get('expires_in', 7200) - 300
        return resp['access_token']
    return None


def _get_wework_user_id(code):
    token = _get_wework_access_token()
    if not token:
        return None
    url = f'https://qyapi.weixin.qq.com/cgi-bin/auth/getuserinfo?access_token={token}&code={code}'
    resp = http_requests.get(url, timeout=10).json()
    if resp.get('errcode') == 0:
        return resp.get('userid') or resp.get('user_info', {}).get('userid')
    return None


def _get_wework_user_detail(userid):
    token = _get_wework_access_token()
    if not token:
        return None
    url = f'https://qyapi.weixin.qq.com/cgi-bin/user/get?access_token={token}&userid={userid}'
    resp = http_requests.get(url, timeout=10).json()
    if resp.get('errcode') == 0:
        return resp
    return None


@auth_bp.route('/login', methods=['GET', 'POST'])
def login():
    code = request.args.get('code')
    if code and request.method == 'GET':
        userid = _get_wework_user_id(code)
        if userid:
            user = User.query.filter_by(username=userid).first()
            if not user:
                detail = _get_wework_user_detail(userid)
                display_name = detail.get('name', userid) if detail else userid
                user = User(
                    username=userid,
                    password_hash=generate_password_hash('wework_auto'),
                    display_name=display_name,
                    role='sales'
                )
                db.session.add(user)
                db.session.commit()
            login_user(user, remember=True)
            next_page = request.args.get('state') or '/'
            return redirect(next_page)

    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        user = User.query.filter_by(username=username).first()
        if user and check_password_hash(user.password_hash, password):
            login_user(user)
            return redirect(url_for('quote.index'))
        flash('作世名序和完戻≾≃', 'error')
    return render_template('auth/login.html')


@auth_bp.route('/wework')
def wework_login():
    corp_id = current_app.config['UEWORK_CORP_ID']
    agent_id = current_app.config['WEWORK_AGENT_ID']
    redirect_uri = request.host_url.rstrip('/') + url_for('auth.login')
    redirect_uri_encoded = urllib.parse.quote(redirect_uri, safe='')
    state = request.args.get('next', '/')
    url = f'https://open.weixin.qq.com/connect/oauth2/authorize?appid={corp_id}&redirect_uri={redirect_uri_encoded}&response_type=code&scope=snsapi_privateinfo&agentid={agent_id}&state={state}#wechat_redirect'
    return redirect(url)


@auth_bp.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('auth.login'))
