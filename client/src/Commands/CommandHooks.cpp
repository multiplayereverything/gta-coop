#include "stdafx.h"
#include "CommandHooks.h"
#include "CCustomCommandMgr.h"
#include "Commands/CCommandAddChatMessage.h"
#include "CAutoTest.h"
#include "CMissionStartSync.h"

uint16_t nCommand = 0x0;
CRunningScript* pScript = nullptr;

bool ProcessCustomCommand()
{
	// if is in custom command range
	uint16_t commandNormalised = (nCommand & 0x7FFF);

	// autotest passmission: answer the debug "S pressed" check of the mission script with true
	if (commandNormalised == 0x0735 && CAutoTest::ms_bPassRequested && pScript->m_bIsMission)
	{
		pScript->m_pCurrentIP += 2;
		pScript->m_bNotFlag = (nCommand & 0x8000) != 0;
		pScript->CollectParameters(1);
		bool pressed = ScriptParams[0] == 83;
		if (pressed)
		{
			CAutoTest::ms_bPassRequested = false;
			CAutoTest::Event("debug_pass_taken", "\"script\":\"" + std::string(pScript->m_szName, strnlen(pScript->m_szName, 8)) + "\"");
		}
		pScript->UpdateCompareFlag(pressed);
		return true;
	}
	// load_and_launch_mission_internal on a partner's game (its contact script saw this player in a mission marker):
	// story missions run on the host's game, so ask the host instead of starting it here alone
	if (commandNormalised == 0x0417 && !CLocalPlayer::m_bIsHost && CNetwork::m_bAuthenticated)
	{
		uint8_t* ip = pScript->m_pCurrentIP;
		pScript->m_pCurrentIP += 2;
		pScript->CollectParameters(1);
		if (CMissionStartSync::InterceptScriptLaunch(pScript, ScriptParams[0]))
			return true;
		pScript->m_pCurrentIP = ip;  // not a story mission (side jobs, minigames): the game runs it as usual
		return false;
	}
	if (commandNormalised >= CCustomCommandMgr::MIN_CUSTOM_COMMAND && commandNormalised <= CCustomCommandMgr::MAX_CUSTOM_COMMAND)
	{
		pScript->m_pCurrentIP += 2;
		pScript->m_bNotFlag = (nCommand & 0x8000) != 0;
		CCustomCommandMgr::ProcessCommand(commandNormalised, pScript); // process it
		return true;
	}
	return false;
}


void __declspec(naked) CRunningScript__Process_Hook() 
{
	__asm
	{
		mov ax, [ecx]

		mov nCommand, ax
		mov pScript, esi

		push eax
		push ecx
		push esi

		call ProcessCustomCommand

		test al, al
		jz process_orig_opcode 

		pop esi
		pop ecx
		pop eax
		push 0x469FB0
		ret

	process_orig_opcode:
		pop esi
		pop ecx
		pop eax
		push 0x469FBF
		ret
	}
}

//uintptr_t CRunningScript__ProcessOneCommand_Ret = 0x469EBF;
//uintptr_t CRunningScript__ProcessOneCommand_Exit = 0x469EF8;
//void __declspec(naked) CRunningScript__ProcessOneCommand_Hook()
//{
//	__asm
//	{
//		xor eax, eax
//		mov ax, [edx]
//
//		mov nCommand, ax
//		mov pScript, ecx
//
//		pushad
//		pushfd
//	}
//
//	if (ProcessCustomCommand(nCommand, pScript))
//	{
//		__asm
//		{
//			popfd
//			popad
//
//			jmp CRunningScript__ProcessOneCommand_Exit
//		}
//	}
//
//	__asm
//	{
//		popfd
//		popad
//
//		jmp CRunningScript__ProcessOneCommand_Ret
//	}
//}

void CommandHooks::InjectHooks()
{
	patch::RedirectJump(0x469FBA, CRunningScript__Process_Hook);
	///patch::RedirectJump(0x469EBA, CRunningScript__ProcessOneCommand_Hook);
}
