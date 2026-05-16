import { db } from '@/lib/db';
import { NextResponse } from 'next/server';

export async function PATCH(
  request: Request,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const body = await request.json();
    const { name, type, startHour, startMinute, endHour, endMinute, daysOfWeek, allowApps, enabled } = body;

    const schedule = await db.scheduleRule.update({
      where: { id },
      data: {
        ...(name !== undefined && { name }),
        ...(type !== undefined && { type }),
        ...(startHour !== undefined && { startHour }),
        ...(startMinute !== undefined && { startMinute }),
        ...(endHour !== undefined && { endHour }),
        ...(endMinute !== undefined && { endMinute }),
        ...(daysOfWeek !== undefined && { daysOfWeek }),
        ...(allowApps !== undefined && { allowApps }),
        ...(enabled !== undefined && { enabled }),
      },
    });

    return NextResponse.json(schedule);
  } catch (error) {
    console.error('Schedule PATCH error:', error);
    return NextResponse.json({ error: 'Failed to update schedule rule' }, { status: 500 });
  }
}
