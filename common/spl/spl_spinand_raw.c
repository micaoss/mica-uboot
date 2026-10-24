// SPDX-License-Identifier: GPL-2.0+
/*
 * SPL: load U-Boot proper from raw SPI NAND.
 *
 * U-Boot proper is a legacy image at the start of a region of CONFIG_SPL_SPINAND_RAW_SIZE bytes at
 * CONFIG_SPL_SPINAND_RAW_OFFS; bad blocks inside the region are skipped. It is booted only when its header and
 * data CRCs hold.
 */

#include <common.h>
#include <dm.h>
#include <errno.h>
#include <image.h>
#include <spl.h>
#include <linux/mtd/mtd.h>

static struct mtd_info *spl_spinand_mtd(void)
{
	struct udevice *dev;

	if (uclass_get_device_by_driver(UCLASS_MTD, DM_DRIVER_GET(spinand), &dev))
		return NULL;
	return dev_get_uclass_priv(dev);
}

/* Read len bytes from the start of the region [start, start + size), skipping its bad blocks. */
static int spl_spinand_read_region(struct mtd_info *mtd, loff_t start, loff_t size, size_t len, void *dst)
{
	loff_t block, end = start + size;
	u8 *to = dst;

	for (block = start; len; block += mtd->erasesize) {
		size_t chunk = min_t(size_t, len, mtd->erasesize), got;
		int ret;

		if (block >= end)
			return -ENOSPC;
		if (mtd_block_isbad(mtd, block))
			continue;
		/* -EUCLEAN: bitflips the on-die ECC corrected; the data is good. */
		ret = mtd_read(mtd, block, chunk, &got, to);
		if ((ret && ret != -EUCLEAN) || got != chunk)
			return -EIO;
		to += chunk;
		len -= chunk;
	}
	return 0;
}

static int spl_spinand_raw_read(struct mtd_info *mtd, struct spl_image_info *spl_image,
				struct spl_boot_device *bootdev)
{
	const loff_t start = CONFIG_SPL_SPINAND_RAW_OFFS, size = CONFIG_SPL_SPINAND_RAW_SIZE;
	struct image_header *header;
	int ret;

	header = spl_get_load_buffer(-sizeof(*header), sizeof(*header));
	ret = spl_spinand_read_region(mtd, start, size, sizeof(*header), header);
	if (ret)
		return ret;
	if (image_get_magic(header) != IH_MAGIC || !image_check_hcrc(header))
		return -EBADMSG;
	ret = spl_parse_image_header(spl_image, bootdev, header);
	if (ret)
		return ret;
	if (spl_image->size > size)
		return -EFBIG;
	/* The legacy image loads with its header, at the image's load address less the header. */
	header = (struct image_header *)spl_image->load_addr;
	ret = spl_spinand_read_region(mtd, start, size, spl_image->size, header);
	if (ret)
		return ret;
	if (!image_check_hcrc(header) || !image_check_dcrc(header))
		return -EBADMSG;
	return 0;
}

static int spl_spinand_raw_load_image(struct spl_image_info *spl_image, struct spl_boot_device *bootdev)
{
	struct mtd_info *mtd = spl_spinand_mtd();
	int ret;

	if (!mtd)
		return -ENODEV;
	ret = spl_spinand_raw_read(mtd, spl_image, bootdev);
	printf("SPL: U-Boot at 0x%x: %s (%d)\n", (unsigned int)CONFIG_SPL_SPINAND_RAW_OFFS,
	       ret ? "invalid" : "loaded", ret);
	return ret;
}

SPL_LOAD_IMAGE_METHOD("SPI NAND (raw)", 0, BOOT_DEVICE_SPINAND, spl_spinand_raw_load_image);
