#pragma once

struct CTextSegment
{
	std::wstring text;
	D3DCOLOR color;
	int width = -1;  // cached CDXFont::GetTextWidth (chat lines are drawn every frame)
	uint32_t widthFont = 0;
};

class CDXFont
{
public:
	static inline constexpr uint8_t m_iShadowSize = 1;

	static ID3DXFont* m_pD3DXFont;
	static ID3DXSprite* m_pSprite;
	static inline ID3DXSprite* ms_pBatch = nullptr;  // set between BeginBatch and EndBatch
	static inline uint32_t ms_nFontGeneration = 0;

	// all DrawText calls in between go through one sprite: one set of render states instead of one per call
	static void BeginBatch();
	static void EndBatch();
	struct Batch { Batch() { BeginBatch(); } ~Batch() { EndBatch(); } };
	static uint8_t m_fFontSize;

	static void Init();
	static void Draw(int x, int y, const std::vector<CTextSegment>& segments);
	static void Draw(int x, int y, const std::string& str, D3DCOLOR defaultColor);
	static void Draw(int x, int y, const std::wstring& str, D3DCOLOR defaultColor);
	static void DrawSegmentWithShadow(int x, int y, const wchar_t* text, D3DCOLOR color);
	static int GetTextWidth(const std::wstring& seg);
	static int GetTextWidth(CTextSegment& seg);
	static std::vector<CTextSegment> ParseColorSegments(const std::wstring& input, D3DCOLOR defaultColor);

private:
	static void InitFont();
	static void DestroyFont();
};