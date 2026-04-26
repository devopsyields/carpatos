#!/bin/sh
# build.sh — instaleaza tema Plymouth CarpatOS
#
# Theme path: /usr/share/plymouth/themes/carpatos/
# Activare la ISO build:
#   plymouth-set-default-theme -R carpatos
set -eu

T="$DESTDIR/usr/share/plymouth/themes/carpatos"
install -d "$T"

# Config theme
cat > "$T/carpatos.plymouth" <<'EOF'
[Plymouth Theme]
Name=CarpatOS
Description=CarpatOS Desktop boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/carpatos
ScriptFile=/usr/share/plymouth/themes/carpatos/carpatos.script
EOF

# Script de animatie. Plymouth.script DSL — sintaxa similara JS dar
# limitata. Fara PNG: doar text + dreptunghiuri.
cat > "$T/carpatos.script" <<'EOF'
# carpatos.script — boot splash CarpatOS, fara assets PNG.

W = Window.GetWidth();
H = Window.GetHeight();

# Gradient cer-noapte (top->bottom).
Window.SetBackgroundTopColor(0.10, 0.16, 0.30);
Window.SetBackgroundBottomColor(0.02, 0.04, 0.08);

# Titlu CarpatOS — culoare cream, font mare bold.
title_img = Image.Text("CarpatOS", 0.96, 0.90, 0.83, 1, "Sans Bold 64");
title = Sprite(title_img);
title.SetX((W - title_img.GetWidth()) / 2);
title.SetY(H * 0.45);

# Subtitlu Desktop 1.0 — auriu.
sub_img = Image.Text("Desktop 1.0", 0.83, 0.63, 0.29, 1, "Sans 24");
sub = Sprite(sub_img);
sub.SetX((W - sub_img.GetWidth()) / 2);
sub.SetY(H * 0.45 + title_img.GetHeight() + 14);

# Bara de progres simpla — 3 puncte care pulseaza in faza diferita.
# Folosim Image.Text cu un caracter unicode "•" si schimbam alpha.
dots_count = 3;
dots = [];
dot_spacing = 24;
dots_total_w = (dots_count - 1) * dot_spacing;
for (i = 0; i < dots_count; i++) {
    img = Image.Text("•", 0.83, 0.63, 0.29, 1, "Sans Bold 32");
    s = Sprite(img);
    s.SetX((W - dots_total_w) / 2 + i * dot_spacing - img.GetWidth() / 2);
    s.SetY(H * 0.45 + title_img.GetHeight() + 70);
    dots[i] = s;
}

# Animatie pulsare puncte.
fun refresh_cb() {
    t = Plymouth.GetBootProgress() * 4.0;
    for (i = 0; i < dots_count; i++) {
        phase = t * 2 - i * 0.5;
        alpha = (Math.Cos(phase) + 1) / 2;
        if (alpha < 0.25) alpha = 0.25;
        dots[i].SetOpacity(alpha);
    }
}
Plymouth.SetRefreshFunction(refresh_cb);

# La afisarea unui mesaj (parola disc, etc.) — il punem sub puncte.
msg = NULL;
fun message_cb(text) {
    if (msg) msg = NULL;
    img = Image.Text(text, 0.95, 0.95, 0.95, 1, "Sans 16");
    msg = Sprite(img);
    msg.SetX((W - img.GetWidth()) / 2);
    msg.SetY(H * 0.45 + title_img.GetHeight() + 130);
}
Plymouth.SetMessageFunction(message_cb);

# Dialog parola — afisam un input text simplu sub puncte.
prompt_img = NULL;
fun display_password_cb(prompt, bullets) {
    str = prompt + ": " + StringBuffer().AppendChar(0x2022).ToString() * bullets;
    if (prompt_img) prompt_img = NULL;
    img = Image.Text(str, 0.96, 0.90, 0.83, 1, "Sans 18");
    prompt_img = Sprite(img);
    prompt_img.SetX((W - img.GetWidth()) / 2);
    prompt_img.SetY(H * 0.45 + title_img.GetHeight() + 170);
}
Plymouth.SetDisplayPasswordFunction(display_password_cb);

fun display_normal_cb() {
    if (prompt_img) prompt_img = NULL;
}
Plymouth.SetDisplayNormalFunction(display_normal_cb);
EOF

chmod 0644 "$T/carpatos.plymouth" "$T/carpatos.script"
