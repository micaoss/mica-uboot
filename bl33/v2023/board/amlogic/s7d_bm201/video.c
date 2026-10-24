// SPDX-License-Identifier: GPL-2.0+
/* Board-local video adapter for the vendor S7D OSD framebuffer. */

#include <common.h>
#include <dm.h>
#include <env.h>
#include <video.h>
#include <amlogic/color.h>
#include <amlogic/media/vout/aml_vout.h>
#include <amlogic/video_fb.h>

#define HDMI_CONSOLE_BYTES_PER_PIXEL 2

extern GraphicDevice fb_gdev;

static bool s7d_bm201_osd_geometry_supported(uint width, uint height)
{
	return (width == 1280 && height == 720) ||
	       (width == 1920 && height == 1080);
}

int s7d_bm201_osd_video_prepare(void)
{
	struct vinfo_s *vinfo;
	ulong width;
	ulong height;
	int ret;

	/* Refresh geometry after vout has resolved any EDID fallback mode. */
	vout_init();
	vinfo = vout_get_current_vinfo();
	if (!vinfo)
		return -ENODEV;
	width = vinfo->width;
	height = vinfo->height;

	if (!s7d_bm201_osd_geometry_supported(width, height)) {
		printf("HDMI console: unsupported output geometry %lux%lu\n",
		       width, height);
		return -EINVAL;
	}

	ret = env_set_ulong("fb_width", width);
	ret |= env_set_ulong("fb_height", height);
	if (ret)
		return ret;

	printf("HDMI console: selected %lux%lu OSD geometry\n",
	       width, height);
	return 0;
}

static int s7d_bm201_osd_video_probe(struct udevice *dev)
{
	struct video_uc_plat *plat = dev_get_uclass_plat(dev);
	struct video_priv *priv = dev_get_uclass_priv(dev);
	ulong size;

	if (!fb_gdev.frameAdrs ||
	    !s7d_bm201_osd_geometry_supported(fb_gdev.fb_width,
					       fb_gdev.fb_height) ||
	    fb_gdev.gdfBytesPP != HDMI_CONSOLE_BYTES_PER_PIXEL ||
	    fb_gdev.gdfIndex != COLOR_INDEX_16_565) {
		printf("HDMI console: unsupported OSD framebuffer %x %ux%u@%u format %u\n",
		       fb_gdev.frameAdrs, fb_gdev.fb_width, fb_gdev.fb_height,
		       fb_gdev.gdfBytesPP * 8, fb_gdev.gdfIndex);
		return -EINVAL;
	}

	size = fb_gdev.fb_width * fb_gdev.fb_height * fb_gdev.gdfBytesPP;
	plat->base = fb_gdev.frameAdrs;
	plat->size = size;
	priv->xsize = fb_gdev.fb_width;
	priv->ysize = fb_gdev.fb_height;
	priv->bpix = VIDEO_BPP16;
	video_set_flush_dcache(dev, true);

	printf("HDMI console: using OSD framebuffer at 0x%x (%ux%u@16)\n",
	       fb_gdev.frameAdrs, fb_gdev.fb_width, fb_gdev.fb_height);
	return 0;
}

static const struct udevice_id s7d_bm201_osd_video_ids[] = {
	{ .compatible = "amlogic,s7d-bm201-osd-video" },
	{ }
};

U_BOOT_DRIVER(s7d_bm201_osd_video) = {
	.name = "s7d_bm201_osd_video",
	.id = UCLASS_VIDEO,
	.of_match = s7d_bm201_osd_video_ids,
	.probe = s7d_bm201_osd_video_probe,
};
