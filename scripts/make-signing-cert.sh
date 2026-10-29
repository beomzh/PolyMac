#!/usr/bin/env bash
# 배포용 자체 서명 코드 서명 인증서 "PolyMac Beomzh" 만들기 (docs/RELEASING.md 4-6)
#
#   scripts/make-signing-cert.sh [백업 파일 경로]
#
# - 이름에 개인정보(이메일·실명·팀 ID)가 들어가지 않는다
# - 10년 유효 — 매년 바꾸면 받는 사람의 macOS 권한이 매번 풀린다
# - 로그인 키체인에 넣고, 코드 서명 용도로만 신뢰한다 (macOS가 암호/Touch ID를 묻는다)
# - 같은 인증서를 다시 만들 수는 없으니 백업(.p12, 기본 ~/Documents/PolyMac-signing.p12)을 안전한 곳에 보관한다
#   다른 Mac에서는: security import <백업> -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign
set -euo pipefail

NAME="PolyMac Beomzh"
DAYS=3650
BACKUP="${1:-$HOME/Documents/PolyMac-signing.p12}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" > /dev/null 2>&1; then
    echo "✗ 키체인에 이미 \"$NAME\" 인증서가 있습니다 — 그것을 계속 쓰세요 (새로 만들면 권한이 풀립니다)"
    exit 1
fi
[[ ! -e "$BACKUP" ]] || { echo "✗ 백업 파일이 이미 있습니다: $BACKUP"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
chmod 700 "$WORK"

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

echo "▶ 인증서 만들기 — $NAME, ${DAYS}일"
openssl req -x509 -newkey rsa:3072 -sha256 -nodes -days "$DAYS" \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2> /dev/null

echo "▶ 백업 암호 (백업 파일을 다시 가져올 때 필요, 화면에 보이지 않음)"
read -r -s -p "  암호: " PASS; echo
read -r -s -p "  한 번 더: " PASS2; echo
[[ -n "$PASS" && "$PASS" == "$PASS2" ]] || { echo "✗ 암호가 비었거나 서로 다릅니다"; exit 1; }
export POLYMAC_P12_PASS="$PASS"
unset PASS PASS2

# OpenSSL 3은 macOS 키체인이 읽는 예전 형식으로 내보내야 한다
LEGACY=()
openssl version | grep -q '^OpenSSL 3' && LEGACY=(-legacy)
mkdir -p "$(dirname "$BACKUP")"
(umask 077 && openssl pkcs12 -export "${LEGACY[@]}" -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$BACKUP" -passout env:POLYMAC_P12_PASS)

echo "▶ 로그인 키체인에 넣기 (codesign만 키를 쓰도록)"
security import "$BACKUP" -k "$KEYCHAIN" -f pkcs12 -P "$POLYMAC_P12_PASS" -T /usr/bin/codesign > /dev/null
unset POLYMAC_P12_PASS

echo "▶ 코드 서명 용도로만 신뢰 — macOS가 암호/Touch ID를 묻습니다"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

if security find-identity -v -p codesigning | grep -qF "\"$NAME\""; then
    echo "✅ \"$NAME\" 준비 완료 — scripts/build-app.sh가 자동으로 이 인증서를 씁니다"
    echo "   백업: $BACKUP  (USB·암호 관리자 등 안전한 곳으로 옮기세요. 저장소에 넣지 마세요)"
    echo "   다음: scripts/build-app.sh --install 후 손쉬운 사용·화면 녹음 권한을 한 번 다시 허용"
else
    echo "✗ 키체인에는 들어갔지만 서명용으로 보이지 않습니다 — security find-identity -p codesigning 결과를 확인하세요"
    exit 1
fi
