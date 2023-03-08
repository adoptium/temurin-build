/**
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
################################################################################
*/

#include <stdio.h>
#include <windows.h>

int main(int argc, char** argv) {
    char *file;
    if (argc > 1) {
        file = argv[1];
    } else {
        printf("Syntax: UpdateVsVersionInfo <file>\n");
	return 1;
    }

    DWORD   dwHandle, dwInfoSize;

    // Get the VS_VERSION_INFO size 
    dwInfoSize = GetFileVersionInfoSize(file, &dwHandle);
    if (dwInfoSize > 0)
    {
        // Allocate lpBuf for existing info
        unsigned char* lpBuf = (unsigned char*)malloc(dwInfoSize);
        // Allocate lpBufNew for creation of new info, add extra 256bytes for enough space
        unsigned char* lpBufNew = (unsigned char*)malloc(dwInfoSize+256);

        // Get existing version info structure 
        GetFileVersionInfo(file, 0, dwInfoSize, lpBuf);

        LPTSTR pValueBuffer;

        HANDLE hResource = BeginUpdateResource(file, FALSE);
        if (NULL != hResource)
        {
            UINT uTemp;
	    struct {
                WORD wLang;
		WORD wCP;
	    } *lpTranslate;

            //  Get language info
	    if (!VerQueryValue(lpBuf, "\\VarFileInfo\\Translation", (LPVOID *)&lpTranslate, &uTemp) != FALSE)
            {
                printf("Error: Unable to query VS_VERSION_INFO language info\n");
                return 1;
            }

            // Analyse VS_VERSION_INFO
            // See https://learn.microsoft.com/en-us/windows/win32/menurc/vs-versioninfo?source=recommendations
        
            unsigned char *ptr = (unsigned char *)lpBuf;

            // WORD wLength
            short versionInfoLen = *((short *)ptr);
            unsigned char * pVersionInfoEnd = ptr + versionInfoLen;
            ptr += 2;

            // WORD wValueLength
            ptr += 2;

            // WORD wType
            ptr += 2;

            // WCHAR - L"VS_VERSION_INFO"
            ptr += ((wcslen(L"VS_VERSION_INFO")+1) * 2); // Length of sz in Unicode

            // Padding to DWORD
            int offset = 4 - ((ptr-((unsigned char *)lpBuf)) % 4);
            if (offset < 4) {
                ptr += offset;
            }
   
            // VS_FIXEDFILEINFO : https://learn.microsoft.com/en-us/windows/win32/api/verrsrc/ns-verrsrc-vs_fixedfileinfo
            VS_FIXEDFILEINFO *pVsFixedFileInfo = (VS_FIXEDFILEINFO *)ptr;
            printf("dwSignature: %02x.%02x.%02x.%02x\n",
                ( pVsFixedFileInfo->dwSignature >> 24 ) & 0xff,
                ( pVsFixedFileInfo->dwSignature >> 16 ) & 0xff,
                ( pVsFixedFileInfo->dwSignature >>  8 ) & 0xff,
                ( pVsFixedFileInfo->dwSignature >>  0 ) & 0xff
            );
            ptr += sizeof(VS_FIXEDFILEINFO);

            // Padding to DWORD
            offset = 4 - ((ptr-((unsigned char *)lpBuf)) % 4);
            if (offset < 4) {
                ptr += offset;
            }

            // Children: StringFileInfo + VarFileInfo

            // StringFileInfo : https://learn.microsoft.com/en-us/windows/win32/menurc/stringfileinfo
            unsigned char * pStringFileInfo = ptr;

            // WORD wLength : fill at end
            ptr += 2;

            // WORD wValueLength
            ptr += 2;

            // WORD wType
            ptr += 2;

            // WCHAR szKey : L"StringFileInfo"
            ptr += ((wcslen(L"StringFileInfo")+1) * 2); // Length of sz in Unicode

            // Padding to DWORD
            offset = 4 - ((ptr-((unsigned char *)lpBuf)) % 4);
            if (offset < 4) {
                ptr += offset;
            }

            // StringTable : https://learn.microsoft.com/en-us/windows/win32/menurc/stringtable
            unsigned char * pStringTable = ptr;

            // WORD wLength
            short stringTableLen = *((short*)pStringTable);
            unsigned char * pStringTableEnd = (pStringTable + stringTableLen);
            ptr += 2;

            // WORD wValueLength 
            ptr += 2;

            // WORD wType
            ptr += 2;

            // WCHAR Block Header : L"040904b0"
            ptr += ((wcslen(L"040904b0")+1) * 2); // Length of sz in Unicode

            // Iterate over the String's : https://learn.microsoft.com/en-us/windows/win32/menurc/string-str
            // Until end of StringTable
            while(ptr < pStringTableEnd) {
                // Padding to DWORD
                offset = 4 - ((ptr-((unsigned char *)lpBuf)) % 4);
                if (offset < 4) {
                   ptr += offset;
                }

                unsigned char * pString = ptr;

                // WORD wLength
                short stringLen = *((short *)pString);
                ptr += 2;

                // WORD wValueLength
                ptr += 2;

                // WORD wType
                ptr += 2;

                // WCHAR szKey
                WCHAR * pKey = (WCHAR *)ptr;
                printf("String: %S = ", pKey);
                ptr += ((wcslen(pKey)+1) * 2);

                // Padding to DWORD
                offset = 4 - ((ptr-((unsigned char *)lpBuf)) % 4);
                if (offset < 4) {
                    ptr += offset;
                }

                // WCHAR szValue
                WCHAR * pValue = (WCHAR *)ptr;
                printf("%S\n", pValue);
               
                // Move to next String
                ptr = pString + stringLen; 
            }

	    // Padding to DWORD
            offset = 4 - ((ptr-((unsigned char *)lpBuf)) % 4);
            if (offset < 4) {
                ptr += offset;
            }

	    // VarFileInfo : https://learn.microsoft.com/en-us/windows/win32/menurc/varfileinfo
            unsigned char * pVarFileInfo = ptr;

            // WORD wLength
            int varFileInfoLen = *((int *)pVarFileInfo);
            unsigned char * pVarFileInfoEnd = (pVarFileInfo + varFileInfoLen);
            ptr += 2;

            // WORD wValueLength
            ptr += 2;

            // WORD wType
            ptr += 2;

            // WCHAR : L"VarFileInfo"
            ptr += ((wcslen(L"VarFileInfo")+1) * 2); // Length of sz in Unicode

            // Iterate over the Var's : https://learn.microsoft.com/en-us/windows/win32/menurc/var-str
            // Until end of VarFileInfo
            while(ptr < pVarFileInfoEnd) {
                // Padding to DWORD
                offset = 4 - ((ptr-((unsigned char *)lpBuf)) % 4);
                if (offset < 4) {
                   ptr += offset;
                }

                unsigned char * pVar = ptr;

                // WORD wLength
                short varLen = *((short *)pVar);
                unsigned char * pVarEnd = pVar + varLen;
                ptr += 2;

                // WORD wValueLength
                ptr += 2;

                // WORD wType
                ptr += 2;

                // WCHAR szKey
                WCHAR * pKey = (WCHAR *)ptr;
                printf("Var: %S = ", pKey);
                ptr += ((wcslen(pKey)+1) * 2);

                // Padding to DWORD
                offset = 4 - ((ptr-((unsigned char *)lpBuf)) % 4);
                if (offset < 4) {
                    ptr += offset;
                }

		// Iterate DWORD Value list
                DWORD * pValue = (DWORD *)ptr;
		while((unsigned char *)pValue < pVarEnd) {
                    printf("DWORD: %02x.%02x.%02x.%02x\n",
                              ( (*pValue) >> 24 ) & 0xff,
                              ( (*pValue) >> 16 ) & 0xff,
                              ( (*pValue) >>  8 ) & 0xff,
                              ( (*pValue) >>  0 ) & 0xff
                    );
		    pValue++;
		}
                printf("\n");
               
                // Move to next Var
                ptr = pVar + varLen; 
            }

	    printf("ptr = %x\n", (int)ptr);
	    printf("versionInfoEnd = %x\n", (int)pVersionInfoEnd);

            if (UpdateResource(hResource,
                               RT_VERSION,
                               MAKEINTRESOURCE(VS_VERSION_INFO),
                               lpTranslate->wLang, // or 0
                               lpBuf,
                               dwInfoSize) != FALSE)
            {
                EndUpdateResource(hResource, FALSE);
            }
        }
        free(lpBuf);
        free(lpBufNew);
    } else {
        printf("Error: No VS_VERSION_INFO found in %s", file);
	return 1;
    }

    return 0;       
}

