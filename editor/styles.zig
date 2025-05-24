const c = @import("clibs");

pub fn defaultStyles() void {
    const style = c.ImGui_GetStyle();

    style.*.Alpha = 1.0;
    style.*.DisabledAlpha = 0.50;

    style.*.WindowPadding = c.ImVec2{ .x = 8.0, .y = 8.0 };
    style.*.WindowRounding = 4.0;
    style.*.WindowBorderSize = 0.0;
    style.*.WindowTitleAlign = c.ImVec2{ .x = 0.5, .y = 0.5 };
    style.*.WindowMenuButtonPosition = c.ImGuiDir_Right;
    style.*.ChildRounding = 4.0;
    style.*.ChildBorderSize = 0.0;
    style.*.PopupRounding = 4.0;
    style.*.PopupBorderSize = 0.0;
    style.*.FramePadding = c.ImVec2{ .x = 6.0, .y = 4.0 };
    style.*.FrameRounding = 4.0;
    style.*.FrameBorderSize = 0.0;
    style.*.ItemSpacing = c.ImVec2{ .x = 8.0, .y = 4.0 };
    style.*.ItemInnerSpacing = c.ImVec2{ .x = 6.0, .y = 6.0 };
    style.*.CellPadding = c.ImVec2{ .x = 6.0, .y = 4.0 };
    style.*.IndentSpacing = 20.0;
    style.*.ColumnsMinSpacing = 8.0;
    style.*.ScrollbarSize = 16.0;
    style.*.ScrollbarRounding = 4.0;
    style.*.GrabMinSize = 12.0;
    style.*.GrabRounding = 4.0;
    style.*.TabRounding = 4.0;
    style.*.TabBorderSize = 0.0;
    style.*.ColorButtonPosition = c.ImGuiDir_Right;
    style.*.ButtonTextAlign = c.ImVec2{ .x = 0.5, .y = 0.5 };
    style.*.SelectableTextAlign = c.ImVec2{ .x = 0.5, .y = 0.5 };

    style.*.AntiAliasedLines = true;
    style.*.AntiAliasedFill = true;
    style.*.CurveTessellationTol = 1.25;

    // Colors
    // --- Backgrounds ---
    style.*.Colors[c.ImGuiCol_WindowBg] = c.ImVec4{ .x = 0.10, .y = 0.10, .z = 0.10, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ChildBg] = c.ImVec4{ .x = 0.12, .y = 0.12, .z = 0.12, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PopupBg] = c.ImVec4{ .x = 0.15, .y = 0.15, .z = 0.15, .w = 0.98 };

    // --- Text ---
    style.*.Colors[c.ImGuiCol_Text] = c.ImVec4{ .x = 0.95, .y = 0.95, .z = 0.95, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TextDisabled] = c.ImVec4{ .x = 0.60, .y = 0.60, .z = 0.60, .w = 1.0 };

    // --- Borders ---
    style.*.Colors[c.ImGuiCol_Border] = c.ImVec4{ .x = 0.20, .y = 0.20, .z = 0.20, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_BorderShadow] = c.ImVec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };

    // --- Frames (Input fields, buttons) ---
    style.*.Colors[c.ImGuiCol_FrameBg] = c.ImVec4{ .x = 0.18, .y = 0.18, .z = 0.18, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_FrameBgHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_FrameBgActive] = c.ImVec4{ .x = 0.20, .y = 0.50, .z = 0.85, .w = 1.0 };

    // --- Title bars ---
    style.*.Colors[c.ImGuiCol_TitleBg] = c.ImVec4{ .x = 0.10, .y = 0.10, .z = 0.10, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TitleBgActive] = c.ImVec4{ .x = 0.10, .y = 0.10, .z = 0.10, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TitleBgCollapsed] = c.ImVec4{ .x = 0.10, .y = 0.10, .z = 0.10, .w = 1.0 };

    // --- Menubar ---
    style.*.Colors[c.ImGuiCol_MenuBarBg] = c.ImVec4{ .x = 0.12, .y = 0.12, .z = 0.12, .w = 1.0 };

    // --- Scrollbars ---
    style.*.Colors[c.ImGuiCol_ScrollbarBg] = c.ImVec4{ .x = 0.12, .y = 0.12, .z = 0.12, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrab] = c.ImVec4{ .x = 0.20, .y = 0.20, .z = 0.20, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrabHovered] = c.ImVec4{ .x = 0.25, .y = 0.25, .z = 0.25, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrabActive] = c.ImVec4{ .x = 0.25, .y = 0.25, .z = 0.25, .w = 1.0 };

    // --- Buttons ---
    style.*.Colors[c.ImGuiCol_Button] = c.ImVec4{ .x = 0.18, .y = 0.18, .z = 0.18, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ButtonHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ButtonActive] = c.ImVec4{ .x = 0.20, .y = 0.50, .z = 0.85, .w = 1.0 };

    // --- Headers (for collapsibles, trees, etc.) ---
    style.*.Colors[c.ImGuiCol_Header] = c.ImVec4{ .x = 0.15, .y = 0.15, .z = 0.15, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_HeaderHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_HeaderActive] = c.ImVec4{ .x = 0.20, .y = 0.50, .z = 0.85, .w = 1.0 };

    // --- Separators ---
    style.*.Colors[c.ImGuiCol_Separator] = c.ImVec4{ .x = 0.20, .y = 0.20, .z = 0.20, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SeparatorHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SeparatorActive] = c.ImVec4{ .x = 0.20, .y = 0.50, .z = 0.85, .w = 1.0 };

    // --- Resize Grips ---
    style.*.Colors[c.ImGuiCol_ResizeGrip] = c.ImVec4{ .x = 0.20, .y = 0.20, .z = 0.20, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ResizeGripHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ResizeGripActive] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };

    // --- Tabs ---
    style.*.Colors[c.ImGuiCol_Tab] = c.ImVec4{ .x = 0.15, .y = 0.15, .z = 0.15, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabHovered] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabActive] = c.ImVec4{ .x = 0.20, .y = 0.50, .z = 0.85, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabUnfocused] = c.ImVec4{ .x = 0.10, .y = 0.10, .z = 0.10, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabUnfocusedActive] = c.ImVec4{ .x = 0.10, .y = 0.10, .z = 0.10, .w = 1.0 };

    // --- Plots ---
    style.*.Colors[c.ImGuiCol_PlotLines] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotLinesHovered] = c.ImVec4{ .x = 0.20, .y = 0.50, .z = 0.85, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotHistogram] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotHistogramHovered] = c.ImVec4{ .x = 0.20, .y = 0.50, .z = 0.85, .w = 1.0 };

    // --- Tables ---
    style.*.Colors[c.ImGuiCol_TableHeaderBg] = c.ImVec4{ .x = 0.15, .y = 0.15, .z = 0.15, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableBorderStrong] = c.ImVec4{ .x = 0.20, .y = 0.20, .z = 0.20, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableBorderLight] = c.ImVec4{ .x = 0.17, .y = 0.17, .z = 0.17, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableRowBg] = c.ImVec4{ .x = 0.12, .y = 0.12, .z = 0.12, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableRowBgAlt] = c.ImVec4{ .x = 0.15, .y = 0.15, .z = 0.15, .w = 1.0 };

    // --- Selection & Drag-Drop ---
    style.*.Colors[c.ImGuiCol_TextSelectedBg] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 0.35 };
    style.*.Colors[c.ImGuiCol_DragDropTarget] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_NavHighlight] = c.ImVec4{ .x = 0.26, .y = 0.59, .z = 0.98, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_NavWindowingHighlight] = c.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.7 };
    style.*.Colors[c.ImGuiCol_NavWindowingDimBg] = c.ImVec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.2 };
    style.*.Colors[c.ImGuiCol_ModalWindowDimBg] = c.ImVec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.3 };
}

// Based on Visual Studio theme
//  Author: "MomoDeve"
// <https://github.com/Patitotective/ImThemes/blob/18fc88af009f19a954b25ff4c87aaf948a1b3c89/themes.toml#L824C1-L824C22>
pub fn visualStudioStyles() void {
    const style = c.ImGui_GetStyle();
    style.*.Alpha = 1.0;
    style.*.DisabledAlpha = 0.6000000238418579;
    style.*.WindowPadding = c.ImVec2{ .x = 8.0, .y = 8.0 };
    style.*.WindowRounding = 0.0;
    style.*.WindowBorderSize = 1.0;
    style.*.WindowMinSize = c.ImVec2{ .x = 32.0, .y = 32.0 };
    style.*.WindowTitleAlign = c.ImVec2{ .x = 0.0, .y = 0.5 };
    style.*.WindowMenuButtonPosition = c.ImGuiDir_Right;
    style.*.ChildRounding = 0.0;
    style.*.ChildBorderSize = 1.0;
    style.*.PopupRounding = 0.0;
    style.*.PopupBorderSize = 1.0;
    style.*.FramePadding = c.ImVec2{ .x = 4.0, .y = 3.0 };
    style.*.FrameRounding = 0.0;
    style.*.FrameBorderSize = 0.0;
    style.*.ItemSpacing = c.ImVec2{ .x = 8.0, .y = 4.0 };
    style.*.ItemInnerSpacing = c.ImVec2{ .x = 4.0, .y = 4.0 };
    style.*.CellPadding = c.ImVec2{ .x = 4.0, .y = 2.0 };
    style.*.IndentSpacing = 21.0;
    style.*.ColumnsMinSpacing = 6.0;
    style.*.ScrollbarSize = 14.0;
    style.*.ScrollbarRounding = 0.0;
    style.*.GrabMinSize = 10.0;
    style.*.GrabRounding = 0.0;
    style.*.TabRounding = 0.0;
    style.*.TabBorderSize = 0.0;
    style.*.ColorButtonPosition = c.ImGuiDir_Right;
    style.*.ButtonTextAlign = c.ImVec2{ .x = 0.5, .y = 0.5 };
    style.*.SelectableTextAlign = c.ImVec2{ .x = 0.0, .y = 0.0 };

    style.*.Colors[c.ImGuiCol_Text] = c.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TextDisabled] = c.ImVec4{ .x = 0.5921568870544434, .y = 0.5921568870544434, .z = 0.5921568870544434, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_WindowBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ChildBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PopupBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Border] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_BorderShadow] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_FrameBg] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_FrameBgHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_FrameBgActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TitleBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TitleBgActive] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TitleBgCollapsed] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_MenuBarBg] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarBg] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrab] = c.ImVec4{ .x = 0.321568638086319, .y = 0.321568638086319, .z = 0.3333333432674408, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrabHovered] = c.ImVec4{ .x = 0.3529411852359772, .y = 0.3529411852359772, .z = 0.3725490272045135, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ScrollbarGrabActive] = c.ImVec4{ .x = 0.3529411852359772, .y = 0.3529411852359772, .z = 0.3725490272045135, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_CheckMark] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SliderGrab] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SliderGrabActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Button] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ButtonHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ButtonActive] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Header] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_HeaderHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_HeaderActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Separator] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SeparatorHovered] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_SeparatorActive] = c.ImVec4{ .x = 0.3058823645114899, .y = 0.3058823645114899, .z = 0.3058823645114899, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ResizeGrip] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ResizeGripHovered] = c.ImVec4{ .x = 0.2000000029802322, .y = 0.2000000029802322, .z = 0.2156862765550613, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_ResizeGripActive] = c.ImVec4{ .x = 0.321568638086319, .y = 0.321568638086319, .z = 0.3333333432674408, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_Tab] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabUnfocused] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TabUnfocusedActive] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotLines] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotLinesHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotHistogram] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_PlotHistogramHovered] = c.ImVec4{ .x = 0.1137254908680916, .y = 0.5921568870544434, .z = 0.9254902005195618, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableHeaderBg] = c.ImVec4{ .x = 0.1882352977991104, .y = 0.1882352977991104, .z = 0.2000000029802322, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableBorderStrong] = c.ImVec4{ .x = 0.3098039329051971, .y = 0.3098039329051971, .z = 0.3490196168422699, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableBorderLight] = c.ImVec4{ .x = 0.2274509817361832, .y = 0.2274509817361832, .z = 0.2470588237047195, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_TableRowBg] = c.ImVec4{ .x = 0.0, .y = 0.0, .z = 0.0, .w = 0.0 };
    style.*.Colors[c.ImGuiCol_TableRowBgAlt] = c.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.05999999865889549 };
    style.*.Colors[c.ImGuiCol_TextSelectedBg] = c.ImVec4{ .x = 0.0, .y = 0.4666666686534882, .z = 0.7843137383460999, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_DragDropTarget] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_NavHighlight] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
    style.*.Colors[c.ImGuiCol_NavWindowingHighlight] = c.ImVec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 0.699999988079071 };
    style.*.Colors[c.ImGuiCol_NavWindowingDimBg] = c.ImVec4{ .x = 0.800000011920929, .y = 0.800000011920929, .z = 0.800000011920929, .w = 0.2000000029802322 };
    style.*.Colors[c.ImGuiCol_ModalWindowDimBg] = c.ImVec4{ .x = 0.1450980454683304, .y = 0.1450980454683304, .z = 0.1490196138620377, .w = 1.0 };
}
