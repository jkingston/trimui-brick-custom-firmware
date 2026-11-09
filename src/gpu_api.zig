// SPDX-License-Identifier: GPL-2.0-only
const std = @import("std");
const c = @import("gpu_abi.zig");

pub const Api = struct {
    glUniform1f: *const @TypeOf(c.glUniform1f),
    glUniform1i: *const @TypeOf(c.glUniform1i),
    glActiveTexture: *const @TypeOf(c.glActiveTexture),
    glGetIntegerv: *const @TypeOf(c.glGetIntegerv),
    glUniform2f: *const @TypeOf(c.glUniform2f),
    glUniform4f: *const @TypeOf(c.glUniform4f),
    eglGetDisplay: *const @TypeOf(c.eglGetDisplay),
    eglInitialize: *const @TypeOf(c.eglInitialize),
    eglTerminate: *const @TypeOf(c.eglTerminate),
    eglGetError: *const @TypeOf(c.eglGetError),
    eglQueryString: *const @TypeOf(c.eglQueryString),
    eglBindAPI: *const @TypeOf(c.eglBindAPI),
    eglChooseConfig: *const @TypeOf(c.eglChooseConfig),
    eglCreatePbufferSurface: *const @TypeOf(c.eglCreatePbufferSurface),
    eglDestroySurface: *const @TypeOf(c.eglDestroySurface),
    eglCreateContext: *const @TypeOf(c.eglCreateContext),
    eglDestroyContext: *const @TypeOf(c.eglDestroyContext),
    eglMakeCurrent: *const @TypeOf(c.eglMakeCurrent),
    eglGetProcAddress: *const @TypeOf(c.eglGetProcAddress),
    glGetError: *const @TypeOf(c.glGetError),
    glGetString: *const @TypeOf(c.glGetString),
    glEnable: *const @TypeOf(c.glEnable),
    glDisable: *const @TypeOf(c.glDisable),
    glClearColor: *const @TypeOf(c.glClearColor),
    glClear: *const @TypeOf(c.glClear),
    glScissor: *const @TypeOf(c.glScissor),
    glGenTextures: *const @TypeOf(c.glGenTextures),
    glDeleteTextures: *const @TypeOf(c.glDeleteTextures),
    glBindTexture: *const @TypeOf(c.glBindTexture),
    glTexParameteri: *const @TypeOf(c.glTexParameteri),
    glGenFramebuffers: *const @TypeOf(c.glGenFramebuffers),
    glDeleteFramebuffers: *const @TypeOf(c.glDeleteFramebuffers),
    glBindFramebuffer: *const @TypeOf(c.glBindFramebuffer),
    glFramebufferTexture2D: *const @TypeOf(c.glFramebufferTexture2D),
    glCheckFramebufferStatus: *const @TypeOf(c.glCheckFramebufferStatus),
    glViewport: *const @TypeOf(c.glViewport),
    glCreateShader: *const @TypeOf(c.glCreateShader),
    glShaderSource: *const @TypeOf(c.glShaderSource),
    glCompileShader: *const @TypeOf(c.glCompileShader),
    glGetShaderiv: *const @TypeOf(c.glGetShaderiv),
    glGetShaderInfoLog: *const @TypeOf(c.glGetShaderInfoLog),
    glDeleteShader: *const @TypeOf(c.glDeleteShader),
    glCreateProgram: *const @TypeOf(c.glCreateProgram),
    glAttachShader: *const @TypeOf(c.glAttachShader),
    glBindAttribLocation: *const @TypeOf(c.glBindAttribLocation),
    glLinkProgram: *const @TypeOf(c.glLinkProgram),
    glGetProgramiv: *const @TypeOf(c.glGetProgramiv),
    glDeleteProgram: *const @TypeOf(c.glDeleteProgram),
    glUseProgram: *const @TypeOf(c.glUseProgram),
    glBindBuffer: *const @TypeOf(c.glBindBuffer),
    glEnableVertexAttribArray: *const @TypeOf(c.glEnableVertexAttribArray),
    glVertexAttribPointer: *const @TypeOf(c.glVertexAttribPointer),
    glTexImage2D: *const @TypeOf(c.glTexImage2D),
    glBlendFunc: *const @TypeOf(c.glBlendFunc),
    glDrawArrays: *const @TypeOf(c.glDrawArrays),
    glGetUniformLocation: *const @TypeOf(c.glGetUniformLocation),
    glPixelStorei: *const @TypeOf(c.glPixelStorei),
};
// SAFETY: init initializes every entry before Display.open can use this table.
pub var api: Api = undefined;
var libraries: [7]?std.DynLib = @splat(null);
var ready = false;

pub fn init() !void {
    if (ready) return;
    const files = [_][]const u8{ "libsrv_um.so", "libusc.so", "libglslcompiler.so", "libIMGegl.so", "libpvrNULL_WSEGL.so", "libEGL.so", "libGLESv2.so" };
    errdefer for (&libraries) |*lib| {
        if (lib.*) |*opened| opened.close();
        lib.* = null;
    };
    for (files, 0..) |file, i| {
        var path: [256]u8 = @splat(0);
        libraries[i] = try std.DynLib.open(try std.fmt.bufPrint(&path, "/usr/lib/brick-gpu/{s}", .{file}));
    }
    inline for (@typeInfo(Api).@"struct".field_names) |name| {
        const library_index = if (comptime std.mem.startsWith(u8, name, "egl")) 5 else 6;
        @field(api, name) = libraries[library_index].?.lookup(@FieldType(Api, name), name) orelse return error.MissingGpuSymbol;
    }
    ready = true;
}
