# 서드파티 고지 (Third-Party Notices)

PolyMac에 포함되거나 함께 배포되는 외부 코드·라이브러리의 저작권과 라이선스를 기록한다.

PolyMac은 아래 외부 라이브러리 하나를 앱과 함께 배포한다. 그 밖에는 Apple이 macOS와 함께 제공하는 시스템 프레임워크(AppKit, ScreenCaptureKit, Vision, App Intents 등)만 쓰며, 이들은 재배포하지 않는다.

## Sparkle
- 출처: https://github.com/sparkle-project/Sparkle (2.10.0, `Sparkle-for-Swift-Package-Manager.zip`, sha256 `17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959`)
- 사용 범위: 의존성 전체 (`PolyMac.app/Contents/Frameworks/Sparkle.framework`, XPC 서비스는 빼고 넣음)
- 라이선스: MIT (함께 들어 있는 외부 코드는 아래 원문에 각자의 라이선스로 표시됨)

```
Copyright (c) 2006-2013 Andy Matuschak.
Copyright (c) 2009-2013 Elgato Systems GmbH.
Copyright (c) 2011-2014 Kornel Lesiński.
Copyright (c) 2015-2017 Mayur Pawashe.
Copyright (c) 2014 C.W. Betts.
Copyright (c) 2014 Petroules Corporation.
Copyright (c) 2014 Big Nerd Ranch.
All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

=================
EXTERNAL LICENSES
=================

bspatch.c and bsdiff.c, from bsdiff 4.3 <http://www.daemonology.net/bsdiff/>:

Copyright 2003-2005 Colin Percival
All rights reserved

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions 
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

--

sais.c and sais.h, from sais-lite (2010/08/07) <https://sites.google.com/site/yuta256/sais>:

The sais-lite copyright is as follows:

Copyright (c) 2008-2010 Yuta Mori All Rights Reserved.

Permission is hereby granted, free of charge, to any person
obtaining a copy of this software and associated documentation
files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use,
copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following
conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

--

Portable C implementation of Ed25519, from https://github.com/orlp/ed25519

Copyright (c) 2015 Orson Peters <orsonpeters@gmail.com>

This software is provided 'as-is', without any express or implied warranty. In no event will the
authors be held liable for any damages arising from the use of this software.

Permission is granted to anyone to use this software for any purpose, including commercial
applications, and to alter it and redistribute it freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not claim that you wrote the
   original software. If you use this software in a product, an acknowledgment in the product
   documentation would be appreciated but is not required.

2. Altered source versions must be plainly marked as such, and must not be misrepresented as
   being the original software.

3. This notice may not be removed or altered from any source distribution.

--

SUSignatureVerifier.m:

Copyright (c) 2011 Mark Hamlin.

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted providing that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
```

---

## 항목 추가 방법

외부 코드를 의존성으로 추가하거나 일부를 가져오면, 같은 커밋에서 아래 형식으로 추가한다.

```
## <프로젝트 이름>
- 출처: <저장소 URL> (<버전 또는 커밋 해시>)
- 사용 범위: <의존성 전체 | 가져온 파일·함수>
- 라이선스: <SPDX ID>

<원본 저작권 표시와 라이선스 전문>
```

가져온 코드 파일 상단에는 출처 주석도 남긴다:

```swift
// Adapted from <프로젝트> (<URL>), <라이선스>. Copyright (c) <연도> <저작자>.
```
