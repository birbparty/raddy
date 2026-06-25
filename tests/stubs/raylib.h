/*
 * tests/stubs/raylib.h — Minimal C stub for raddy vita compile-only checks.
 *
 * Declares every type and function that src/raddy/backend/raylib_api.nim
 * imports via {.importc, header: "raylib.h".}. Used by:
 *
 *   nim c --compileOnly -d:vita --os:linux --cpu:amd64 --nimcache:/tmp/... \
 *     tests/stubs/vita_surface_check.nim
 *   gcc -std=c99 -fsyntax-only -Itests/stubs ... /tmp/.../@praddy@sbackend@s*.nim.c
 *
 * This stub is NOT the real raylib — it provides just enough C surface for
 * the Nim compiler to verify types and function signatures. No implementations
 * are provided; the --compileOnly flag skips linking.
 *
 * NAMING NOTES:
 *   - naylib (desktop) renames Rectangle → rlRectangle and DrawTextEx →
 *     rlDrawTextEx to avoid Win32 namespace collisions. raddy's raylib_api.nim
 *     uses those renamed symbols.
 *   - The vita raylib_console port may use the original names (Rectangle,
 *     DrawTextEx). If so, add `when defined(vita): typedef Rectangle rlRectangle`
 *     guards in raylib_api.nim, or teach the host stub to alias them.
 *   - This stub provides BOTH forms so the compile-only check passes under
 *     any naming convention. The real vita integration test is raddy-tzc.
 *
 * Symbols verified as present in naylib's raylib.h (via verify_raylib_codegen.nim):
 *   DrawRectangleRec, DrawRectangleLinesEx, DrawRectangleRounded,
 *   DrawRectangleRoundedLinesEx, DrawRectangleGradientEx,
 *   DrawLineEx, DrawLineStrip, DrawTriangle, DrawTriangleLines,
 *   DrawRing, DrawCircleSector,
 *   DrawTextureRec, BeginScissorMode, EndScissorMode.
 *
 * Symbols that need vita verification (raddy-tzc):
 *   DrawRectangleRoundedLinesEx — added in raylib 4.5; check vita port version.
 *   DrawRectangleGradientEx    — check corner-color parameter order on vita.
 *   DrawLineStrip              — may be absent on older vita ports.
 *   DrawRing                   — may be absent on older vita ports.
 *   rlDrawTextEx / DrawTextEx  — naming differs between naylib and vita console.
 *
 * Symbols confirmed NO-OP on vita (guarded in raylib_api.nim):
 *   DrawEllipse, DrawEllipseLines — vita stub compiles to discard.
 */

#pragma once

/* -------------------------------------------------------------------------
 * Core types
 * ------------------------------------------------------------------------- */

typedef struct { unsigned char r, g, b, a; } Color;

typedef struct { float x, y; } Vector2;

/* naylib desktop renames Rectangle → rlRectangle. Provide both for compat. */
typedef struct { float x, y, width, height; } Rectangle;
typedef Rectangle rlRectangle;

typedef struct {
    unsigned int id;
    int          width;
    int          height;
    int          mipmaps;
    int          format;
} Texture2D;

typedef struct {
    int       baseSize;
    int       glyphCount;
    int       glyphPadding;
    Texture2D texture;   /* embedded by value, same as real raylib Font */
    Rectangle *recs;
    void      *glyphs;   /* GlyphInfo* — we don't access fields; void* is fine */
} Font;

/* -------------------------------------------------------------------------
 * Geometry — filled shapes
 * ------------------------------------------------------------------------- */

void DrawRectangleRec(rlRectangle rec, Color color);
void DrawRectangleLinesEx(rlRectangle rec, float lineThick, Color color);
void DrawRectangleRounded(rlRectangle rec, float roundness, int segments, Color color);
void DrawRectangleRoundedLinesEx(rlRectangle rec, float roundness, int segments, float lineThick, Color color);
void DrawRectangleGradientEx(rlRectangle rec, Color topLeft, Color bottomLeft, Color bottomRight, Color topRight);

void DrawTriangle(Vector2 v1, Vector2 v2, Vector2 v3, Color color);
void DrawTriangleLines(Vector2 v1, Vector2 v2, Vector2 v3, Color color);

void DrawRing(Vector2 center, float innerRadius, float outerRadius,
              float startAngle, float endAngle, int segments, Color color);
void DrawCircleSector(Vector2 center, float radius,
                      float startAngle, float endAngle, int segments, Color color);

/* Ellipse: absent on some vita ports — raddy compiles to no-op under -d:vita */
/* void DrawEllipse(int centerX, int centerY, float radiusH, float radiusV, Color color); */
/* void DrawEllipseLines(int centerX, int centerY, float radiusH, float radiusV, Color color); */

/* -------------------------------------------------------------------------
 * Geometry — lines
 * ------------------------------------------------------------------------- */

void DrawLineEx(Vector2 startPos, Vector2 endPos, float thick, Color color);
void DrawLineStrip(Vector2 *points, int pointCount, Color color);

/* -------------------------------------------------------------------------
 * Text
 * ------------------------------------------------------------------------- */

/* naylib renames DrawTextEx → rlDrawTextEx to avoid Win32 collision.
 * Vita console may use DrawTextEx. Provide both; raddy imports rlDrawTextEx. */
void DrawTextEx(Font font, const char *text, Vector2 position,
                float fontSize, float spacing, Color tint);
#define rlDrawTextEx DrawTextEx

Vector2 MeasureTextEx(Font font, const char *text, float fontSize, float spacing);

/* -------------------------------------------------------------------------
 * Textures
 * ------------------------------------------------------------------------- */

void DrawTextureRec(Texture2D texture, rlRectangle source, Vector2 position, Color tint);

/* -------------------------------------------------------------------------
 * Scissor
 * ------------------------------------------------------------------------- */

void BeginScissorMode(int x, int y, int width, int height);
void EndScissorMode(void);
