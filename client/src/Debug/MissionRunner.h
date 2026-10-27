#pragma once

class MissionRunner
{
public:
	struct SMissionEntry
	{
		const char* m_szName;
		int m_nId;
	};

	static bool DrawUI();
	// the story missions with their mission script ids (main.scm), in story order
	static const SMissionEntry* GetMissions(int& count);
};
