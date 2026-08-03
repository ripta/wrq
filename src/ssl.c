// Copyright (C) 2013 - Will Glozer.  All rights reserved.

#include <pthread.h>
#include <arpa/inet.h>

#include <openssl/evp.h>
#include <openssl/err.h>
#include <openssl/ssl.h>

#include "ssl.h"

static pthread_mutex_t *locks;

static void ssl_lock(int mode, int n, const char *file, int line) {
    pthread_mutex_t *lock = &locks[n];
    if (mode & CRYPTO_LOCK) {
        pthread_mutex_lock(lock);
    } else {
        pthread_mutex_unlock(lock);
    }
}

static unsigned long ssl_id() {
    return (unsigned long) pthread_self();
}

SSL_CTX *ssl_init(const char *cacert, const char *capath,
        const char *client_cert, const char *client_key, bool verify) {
    SSL_CTX *ctx = NULL;

    SSL_load_error_strings();
    SSL_library_init();
    OpenSSL_add_all_algorithms();

    if ((locks = calloc(CRYPTO_num_locks(), sizeof(pthread_mutex_t)))) {
        for (int i = 0; i < CRYPTO_num_locks(); i++) {
            pthread_mutex_init(&locks[i], NULL);
        }

        CRYPTO_set_locking_callback(ssl_lock);
        CRYPTO_set_id_callback(ssl_id);

        if ((ctx = SSL_CTX_new(SSLv23_client_method()))) {
            SSL_CTX_set_mode(ctx, SSL_MODE_AUTO_RETRY);
            SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_CLIENT);

            if (verify) {
                SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
                if (!SSL_CTX_set_default_verify_paths(ctx)) goto error;
                if ((cacert || capath) &&
                        !SSL_CTX_load_verify_locations(ctx, cacert, capath)) {
                    goto error;
                }
            } else {
                SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, NULL);
            }

            if (client_cert) {
                if (!SSL_CTX_use_certificate_chain_file(ctx, client_cert)) {
                    goto error;
                }
                if (!SSL_CTX_use_PrivateKey_file(
                            ctx, client_key, SSL_FILETYPE_PEM)) {
                    goto error;
                }
                if (!SSL_CTX_check_private_key(ctx)) goto error;
            }
        }
    }

    return ctx;

  error:
    SSL_CTX_free(ctx);
    return NULL;
}

status ssl_connect(connection *c, char *host) {
    int r;
    SSL_set_fd(c->ssl, c->fd);
    SSL_set_tlsext_host_name(c->ssl, host);
    if (SSL_get_verify_mode(c->ssl) & SSL_VERIFY_PEER) {
        unsigned char addr[sizeof(struct in6_addr)];
        X509_VERIFY_PARAM *param = SSL_get0_param(c->ssl);
        if (inet_pton(AF_INET, host, addr) == 1 ||
                inet_pton(AF_INET6, host, addr) == 1) {
            if (!X509_VERIFY_PARAM_set1_ip_asc(param, host)) return ERROR;
        } else if (!X509_VERIFY_PARAM_set1_host(param, host, 0)) {
            return ERROR;
        }
    }
    if ((r = SSL_connect(c->ssl)) != 1) {
        switch (SSL_get_error(c->ssl, r)) {
            case SSL_ERROR_WANT_READ:  return RETRY;
            case SSL_ERROR_WANT_WRITE: return RETRY;
            default:                   return ERROR;
        }
    }
    return OK;
}

status ssl_close(connection *c) {
    SSL_shutdown(c->ssl);
    SSL_clear(c->ssl);
    return OK;
}

status ssl_read(connection *c, size_t *n) {
    int r;
    if ((r = SSL_read(c->ssl, c->buf, sizeof(c->buf))) <= 0) {
        switch (SSL_get_error(c->ssl, r)) {
            case SSL_ERROR_WANT_READ:  return RETRY;
            case SSL_ERROR_WANT_WRITE: return RETRY;
            case SSL_ERROR_ZERO_RETURN:
                *n = 0;
                return CLOSED;
            default:                   return ERROR;
        }
    }
    *n = (size_t) r;
    return OK;
}

status ssl_write(connection *c, char *buf, size_t len, size_t *n) {
    int r;
    if ((r = SSL_write(c->ssl, buf, len)) <= 0) {
        switch (SSL_get_error(c->ssl, r)) {
            case SSL_ERROR_WANT_READ:  return RETRY;
            case SSL_ERROR_WANT_WRITE: return RETRY;
            default:                   return ERROR;
        }
    }
    *n = (size_t) r;
    return OK;
}

size_t ssl_readable(connection *c) {
    return SSL_pending(c->ssl);
}
