import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function GET() {
  try {
    const filters = await db.contentFilter.findMany({
      orderBy: { category: 'asc' },
    });

    // Manually resolve device info
    const deviceIds = [...new Set(filters.map(f => f.deviceId).filter(Boolean))] as string[];

    const devices = await db.device.findMany({
      where: { id: { in: deviceIds } },
      select: { id: true, name: true, memberId: true },
    });

    const deviceMap = new Map(devices.map(d => [d.id, d]));

    // Also get member info for devices
    const memberIds = [...new Set(devices.map(d => d.memberId).filter(Boolean))];
    const members = await db.member.findMany({
      where: { id: { in: memberIds } },
      select: { id: true, name: true },
    });
    const memberMap = new Map(members.map(m => [m.id, m]));

    const filtersWithRelations = filters.map(filter => ({
      ...filter,
      device: filter.deviceId ? (() => {
        const device = deviceMap.get(filter.deviceId);
        if (!device) return null;
        return {
          name: device.name,
          member: memberMap.get(device.memberId) || null,
        };
      })() : null,
    }));

    return NextResponse.json(filtersWithRelations);
  } catch (error) {
    console.error('Filters GET error:', error);
    return NextResponse.json({ error: 'Failed to fetch content filters' }, { status: 500 });
  }
}

export async function PATCH(request: Request) {
  try {
    const body = await request.json();
    const { id, enabled, blockLevel } = body;

    if (!id) {
      return NextResponse.json({ error: 'Filter id is required' }, { status: 400 });
    }

    const filter = await db.contentFilter.update({
      where: { id },
      data: {
        ...(enabled !== undefined && { enabled }),
        ...(blockLevel !== undefined && { blockLevel }),
      },
    });

    return NextResponse.json(filter);
  } catch (error) {
    console.error('Filter PATCH error:', error);
    return NextResponse.json({ error: 'Failed to update content filter' }, { status: 500 });
  }
}
